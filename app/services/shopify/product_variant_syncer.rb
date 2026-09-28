require "digest"

module Shopify
  class ProductVariantSyncer
    GET_PRODUCT = <<~GRAPHQL
      query GetProduct($id: ID!) {
        product(id: $id) {
          id
          options {
            id
            name
            optionValues {
              name
            }
          }
          variants(first: 100) {
            nodes {
              id
              title
              sku
              inventoryItem {
                id
              }
              selectedOptions {
                name
                value
              }
            }
          }
        }
      }
    GRAPHQL

    GET_LOCATIONS = <<~GRAPHQL
      query {
        locations(first: 20, query: "active:true") {
          nodes {
            id
            name
            isPrimary
          }
        }
      }
    GRAPHQL

   
    OPTIONS_CREATE = <<~GRAPHQL
      mutation ProductOptionsCreate($productId: ID!, $options: [OptionCreateInput!]!) {
        productOptionsCreate(productId: $productId, options: $options, variantStrategy: LEAVE_AS_IS) {
          product {
            id
            options {
              id
              name
            }
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    BULK_UPDATE = <<~GRAPHQL
      mutation ProductVariantsBulkUpdate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {
        productVariantsBulkUpdate(productId: $productId, variants: $variants) {
          productVariants {
            id
            sku
            inventoryItem {
              id
            }
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    GET_PRODUCT_INVENTORY = <<~GRAPHQL
      query GetProductInventory($id: ID!, $locationId: ID!) {
        product(id: $id) {
          variants(first: 100) {
            nodes {
              sku
              inventoryItem {
                id
                tracked
                inventoryLevel(locationId: $locationId) {
                  id
                  quantities(names: ["available"]) {
                    name
                    quantity
                  }
                }
              }
            }
          }
        }
      }
    GRAPHQL

    INVENTORY_ACTIVATE = <<~GRAPHQL
      mutation InventoryActivate(
        $inventoryItemId: ID!
        $locationId: ID!
        $available: Int!
        $idempotencyKey: String!
      ) {
        inventoryActivate(
          inventoryItemId: $inventoryItemId
          locationId: $locationId
          available: $available
        ) @idempotent(key: $idempotencyKey) {
          inventoryLevel {
            id
            quantities(names: ["available"]) {
              quantity
            }
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    INVENTORY_ITEM_UPDATE = <<~GRAPHQL
      mutation InventoryItemUpdate($id: ID!, $input: InventoryItemInput!) {
        inventoryItemUpdate(id: $id, input: $input) {
          inventoryItem {
            id
            tracked
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    INVENTORY_SET = <<~GRAPHQL
      mutation InventorySetQuantities($input: InventorySetQuantitiesInput!, $idempotencyKey: String!) {
        inventorySetQuantities(input: $input) @idempotent(key: $idempotencyKey) {
          inventoryAdjustmentGroup {
            reason
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    COLOR_OPTION = "Color"
    SIZE_OPTION = "Size"

    def initialize
      @client = Shopify::Client.new
      @location_id = nil
    end

    def sync(product)
      product.reload
      return unless product.from_supplier?
      return if product.shopify_id.blank?

      shopify_product = fetch_shopify_product(product)
      ensure_product_options!(product, shopify_product)

      shopify_product = fetch_shopify_product(product)
      create_missing_variants(product, shopify_product)
      update_existing_variants(product, shopify_product)
      sync_inventory(product)
    end

    private

    def product_gid(product)
      "gid://shopify/Product/#{product.shopify_id}"
    end

    def fetch_shopify_product(product)
      response = @client.query(GET_PRODUCT, { id: product_gid(product) })
      assert_graphql_ok!(response)

      response.dig("data", "product") || raise("Shopify product not found for #{product.id}")
    end

    def ensure_product_options!(product, shopify_product)
      option_names = shopify_product.fetch("options", []).map { |option| option["name"] }
      return if option_names.include?(COLOR_OPTION) && option_names.include?(SIZE_OPTION)

      supplier_variants = product.product_variants.from_supplier
      colors = supplier_variants.map(&:color).compact.uniq
      sizes = supplier_variants.map(&:size).compact.uniq

      return if colors.empty? || sizes.empty?

      response = @client.query(
        OPTIONS_CREATE,
        {
          productId: product_gid(product),
          options: [
            {
              name: COLOR_OPTION,
              values: colors.map { |color| { name: color } }
            },
            {
              name: SIZE_OPTION,
              values: sizes.map { |size| { name: size } }
            }
          ]
        }
      )

      result = response.dig("data", "productOptionsCreate")
      assert_graphql_ok!(response)

      unless result
        raise "Shopify productOptionsCreate returned no result: #{response.inspect}"
      end

      errors = result["userErrors"] || []
      ignorable = errors.all? { |error| error["message"]&.include?("already exists") }

      if errors.any? && !ignorable
        raise errors.inspect
      end
    end

    def create_missing_variants(product, shopify_product)
      variants = product.product_variants.needs_shopify_create.order(:id)
      return if variants.empty?

      remove_standalone = shopify_product.fetch("variants", {}).fetch("nodes", []).size <= 1
      inputs = variants.map { |variant| bulk_input_for_create(variant, shopify_product) }

      response = @client.query(
        bulk_create_mutation(remove_standalone: remove_standalone),
        {
          productId: product_gid(product),
          variants: inputs
        }
      )

      result = response.dig("data", "productVariantsBulkCreate")
      assert_mutation_result!(response, result)

      assign_shopify_ids!(variants, result["productVariants"])
    end

    def update_existing_variants(product, shopify_product)
      variants = product.product_variants.from_supplier.linked_to_shopify.order(:id)
      return if variants.empty?

      inputs = variants.map { |variant| bulk_input_for_update(variant, shopify_product) }

      response = @client.query(
        BULK_UPDATE,
        {
          productId: product_gid(product),
          variants: inputs
        }
      )

      result = response.dig("data", "productVariantsBulkUpdate")
      assert_mutation_result!(response, result)
    end

    def sync_inventory(product)
      location_id = shopify_location_id
      unless location_id
        Rails.logger.warn("[ProductVariantSyncer] No location; skipping inventory sync")
        return
      end

      shopify_product = fetch_shopify_product_inventory(product, location_id)
      shopify_by_sku = index_shopify_variants_by_sku(shopify_product)

      to_activate = []
      missing_skus = []

      product.product_variants.from_supplier.each do |variant|
        if variant.sku.blank?
          missing_skus << variant.id
          next
        end

        shopify_variant = shopify_by_sku[variant.sku]
        unless shopify_variant
          missing_skus << variant.sku
          next
        end

        inventory_item_id = shopify_variant.dig("inventoryItem", "id")
        next unless inventory_item_id

        ensure_inventory_tracked!(inventory_item_id, shopify_variant)

        next if stocked_at_location?(shopify_variant)

        to_activate << {
          sku: variant.sku,
          inventory_item_id: inventory_item_id,
          target_quantity: variant.inventory_quantity.to_i
        }
      end

      if missing_skus.any?
        Rails.logger.warn(
          "[ProductVariantSyncer] product_id=#{product.id} missing Shopify match for: #{missing_skus.join(', ')}"
        )
      end

      activate_inventory_at_location!(to_activate, location_id, product)

      shopify_product = fetch_shopify_product_inventory(product, location_id)
      shopify_by_sku = index_shopify_variants_by_sku(shopify_product)
      to_set = build_inventory_set_payload(product, shopify_by_sku)

      set_inventory_quantities!(to_set, location_id, product)
      verify_inventory_sync!(product, location_id)
    end

    def build_inventory_set_payload(product, shopify_by_sku)
      product.product_variants.from_supplier.filter_map do |variant|
        next if variant.sku.blank?

        shopify_variant = shopify_by_sku[variant.sku]
        next unless shopify_variant

        inventory_item_id = shopify_variant.dig("inventoryItem", "id")
        next unless inventory_item_id
        next unless stocked_at_location?(shopify_variant)

        target = variant.inventory_quantity.to_i
        current = available_quantity_on_shopify(shopify_variant)
        next if current == target

        {
          inventory_item_id: inventory_item_id,
          target_quantity: target,
          change_from_quantity: current.nil? ? 0 : current
        }
      end
    end

    def activate_inventory_at_location!(items, location_id, product)
      items.each do |item|
        response = @client.query(
          INVENTORY_ACTIVATE,
          {
            inventoryItemId: item[:inventory_item_id],
            locationId: location_id,
            available: item[:target_quantity],
            idempotencyKey: inventory_idempotency_key(
              product,
              "#{item[:inventory_item_id]}:#{item[:target_quantity]}",
              "activate"
            )
          }
        )

        assert_graphql_ok!(response)

        result = response.dig("data", "inventoryActivate")
        unless result
          raise "inventoryActivate returned no result: #{response.inspect}"
        end

        errors = result["userErrors"] || []
        next if errors.empty?

        if errors.all? { |error| ignorable_activate_error?(error["message"]) }
          next
        end

        raise errors.inspect
      end
    end

    def ignorable_activate_error?(message)
      return false if message.blank?

      message.match?(/already active|already stocked|already been/i)
    end

    def set_inventory_quantities!(items, location_id, product)
      return if items.empty?

      quantities = items.map do |item|
        {
          inventoryItemId: item[:inventory_item_id],
          locationId: location_id,
          quantity: item[:target_quantity],
          changeFromQuantity: item[:change_from_quantity]
        }
      end

      response = @client.query(
        INVENTORY_SET,
        {
          input: {
            name: "available",
            reason: "correction",
            referenceDocumentUri: "app://shopify-rails-app/products/#{product.id}",
            quantities: quantities
          },
          idempotencyKey: inventory_idempotency_key(
            product,
            quantities.map { |row| "#{row[:inventoryItemId]}:#{row[:quantity]}" }.sort.join("|"),
            "set"
          )
        }
      )

      result = response.dig("data", "inventorySetQuantities")
      assert_mutation_result!(response, result)
    end

    def ensure_inventory_tracked!(inventory_item_id, shopify_variant)
      return if shopify_variant.dig("inventoryItem", "tracked")

      response = @client.query(
        INVENTORY_ITEM_UPDATE,
        {
          id: inventory_item_id,
          input: { tracked: true }
        }
      )

      result = response.dig("data", "inventoryItemUpdate")
      assert_mutation_result!(response, result)
    end

    def stocked_at_location?(shopify_variant)
      shopify_variant.dig("inventoryItem", "inventoryLevel", "id").present?
    end

    def verify_inventory_sync!(product, location_id)
      shopify_product = fetch_shopify_product_inventory(product, location_id)
      shopify_by_sku = index_shopify_variants_by_sku(shopify_product)

      mismatches = []

      product.product_variants.from_supplier.each do |variant|
        next if variant.sku.blank?

        expected = variant.inventory_quantity.to_i
        shopify_variant = shopify_by_sku[variant.sku]
        next unless shopify_variant

        unless stocked_at_location?(shopify_variant)
          mismatches << { sku: variant.sku, expected: expected, actual: "not_stocked_at_location" }
          next
        end

        actual = available_quantity_on_shopify(shopify_variant)
        next if actual == expected

        mismatches << { sku: variant.sku, expected: expected, actual: actual }
      end

      return if mismatches.empty?

      Rails.logger.error(
        "[ProductVariantSyncer] product_id=#{product.id} inventory mismatch after sync: #{mismatches.inspect}"
      )
      raise "Inventory sync verification failed for product #{product.id}: #{mismatches.inspect}"
    end

    def fetch_shopify_product_inventory(product, location_id)
      response = @client.query(
        GET_PRODUCT_INVENTORY,
        { id: product_gid(product), locationId: location_id }
      )
      assert_graphql_ok!(response)

      response.dig("data", "product") || raise("Shopify product not found for #{product.id}")
    end

    def available_quantity_on_shopify(shopify_variant)
      level = shopify_variant.dig("inventoryItem", "inventoryLevel")
      return nil unless level

      quantities = level["quantities"] || []
      return 0 if quantities.empty?

      row = quantities.find { |entry| entry["name"] == "available" } || quantities.first
      return 0 unless row&.key?("quantity")

      row["quantity"].to_i
    end

    def inventory_idempotency_key(product, fingerprint, action)
      stamp = product.product_variants.from_supplier.maximum(:updated_at)&.to_i
      raw = "product-#{product.id}-#{action}-#{stamp}-#{fingerprint}"
      Digest::SHA256.hexdigest(raw)[0, 32]
    end

    def bulk_create_mutation(remove_standalone:)
      strategy = remove_standalone ? "REMOVE_STANDALONE_VARIANT" : "DEFAULT"

      <<~GRAPHQL
        mutation ProductVariantsBulkCreate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {
          productVariantsBulkCreate(productId: $productId, variants: $variants, strategy: #{strategy}) {
            productVariants {
              id
              sku
              inventoryItem {
                id
              }
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL
    end

    def bulk_input_for_create(variant, shopify_product)
      input = {
        price: variant.price.to_s,
        inventoryItem: {
          sku: variant.sku,
          tracked: true
        }
      }

      option_values = option_values_for(variant, shopify_product)
      input[:optionValues] = option_values if option_values.present?

      input
    end

    def bulk_input_for_update(variant, shopify_product)
      input = {
        id: "gid://shopify/ProductVariant/#{variant.shopify_id}",
        price: variant.price.to_s,
        inventoryItem: {
          sku: variant.sku,
          tracked: true
        }
      }

      option_values = option_values_for(variant, shopify_product)
      input[:optionValues] = option_values if option_values.present?

      input
    end

    def option_values_for(variant, shopify_product)
      return unless variant.configurable?

      option_names = shopify_product.fetch("options", []).map { |option| option["name"] }
      return unless option_names.include?(COLOR_OPTION) && option_names.include?(SIZE_OPTION)

      [
        { optionName: COLOR_OPTION, name: variant.color },
        { optionName: SIZE_OPTION, name: variant.size }
      ]
    end

    def assign_shopify_ids!(db_variants, shopify_variants)
      shopify_by_sku = shopify_variants.index_by { |row| row["sku"] }

      db_variants.each do |variant|
        shopify_variant = shopify_by_sku[variant.sku]
        next unless shopify_variant

        variant.update!(shopify_id: shopify_variant["id"].split("/").last)
      end
    end

    def index_shopify_variants_by_sku(shopify_product)
      shopify_product.fetch("variants", {}).fetch("nodes", []).index_by { |row| row["sku"] }
    end

    def shopify_location_id
      @location_id ||= begin
        raw = ENV["SHOPIFY_LOCATION_ID"].presence
        if raw
          raw.start_with?("gid://") ? raw : "gid://shopify/Location/#{raw}"
        else
          fetch_primary_location_id
        end
      end
    end

    def fetch_primary_location_id
      response = @client.query(GET_LOCATIONS)
      assert_graphql_ok!(response)

      nodes = response.dig("data", "locations", "nodes") || []
      primary = nodes.find { |node| node["isPrimary"] } || nodes.first

      if primary
        Rails.logger.info(
          "[ProductVariantSyncer] Using location #{primary['name']} (#{primary['id']})"
        )
      end

      primary&.dig("id")
    end

    def assert_graphql_ok!(response)
      if response["errors"].present?
        raise response["errors"].inspect
      end
    end

    def assert_mutation_result!(response, result)
      assert_graphql_ok!(response)

      unless result
        raise "Shopify mutation returned no result: #{response.inspect}"
      end

      if result["userErrors"].present? && result["userErrors"].any?
        raise result["userErrors"].inspect
      end
    end
  end
end
