module Shopify
  class ProductImporter
    QUERY = <<~GRAPHQL
      query {
        products(first: 50) {
          nodes {
            id
            title
            vendor
            productType
            status

            options {
              id
              name
              values
            }

            variants(first: 50) {
              nodes {
                id
                title
                sku
                price
                inventoryQuantity

                selectedOptions {
                  name
                  value
                }
              }
            }
          }
        }
      }
    GRAPHQL

    def initialize
      @client = Shopify::Client.new
    end

    def call
      response = @client.query(QUERY)

      products = response.dig("data", "products", "nodes") || []

      products.each do |shopify_product|
        shopify_product_id = shopify_product["id"].split("/").last
        variants = shopify_product.dig("variants", "nodes") || []

        # First try to find an existing CSV-backed product
        # through one of its variant SKUs.
        product = find_product_by_variant_sku(variants)

        # If no CSV product exists, find/create by Shopify ID.
        product ||= Product.find_or_initialize_by(shopify_id: shopify_product_id)

        attributes = {
          shopify_id: shopify_product_id,
          title: shopify_product["title"],
          vendor: shopify_product["vendor"],
          product_type: shopify_product["productType"],
          status: shopify_product["status"]
        }

        # CSV / supplier fields remain the source of truth when already set.
        attributes.delete(:title) if product.from_supplier? && product.title.present?
        attributes.delete(:vendor) if product.from_supplier? && product.vendor.present?
        attributes.delete(:product_type) if product.from_supplier? && product.product_type.present?
        attributes.delete(:status) if product.from_supplier? && product.status.present?

        product.update!(attributes)

        variants.each do |shopify_variant|
          shopify_variant_id = shopify_variant["id"].split("/").last
          sku = shopify_variant["sku"]
        
          variant = if sku.present?
            ProductVariant.find_or_initialize_by(sku: sku)
          else
            ProductVariant.find_or_initialize_by(shopify_id: shopify_variant_id)
          end
        
          selected = shopify_variant["selectedOptions"] || []
          color = selected.find { |opt| opt["name"] == "Color" }&.dig("value")
          size = selected.find { |opt| opt["name"] == "Size" }&.dig("value")

          attributes = {
            product: product,
            shopify_id: shopify_variant_id,
            title: shopify_variant["title"],
            price: shopify_variant["price"],
            inventory_quantity: shopify_variant["inventoryQuantity"]
          }

          attributes[:sku] = sku if sku.present?
          attributes[:color] = color if color.present? && variant.color.blank?
          attributes[:size] = size if size.present? && variant.size.blank?

          unless variant.from_supplier?
            variant.update!(attributes)
            next
          end

          # Supplier catalog: only attach Shopify ids — CSV remains source of truth.
          variant.update!(shopify_id: shopify_variant_id)
        end
      end
    end

    private

    def find_product_by_variant_sku(shopify_variants)
      shopify_variants.each do |shopify_variant|
        sku = shopify_variant["sku"]

        next if sku.blank?

        variant = ProductVariant.find_by(sku: sku)

        return variant.product if variant.present?
      end

      nil
    end
  end
end