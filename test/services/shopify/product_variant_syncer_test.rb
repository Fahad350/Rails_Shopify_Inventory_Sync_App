require "test_helper"

module Shopify
  class ProductVariantSyncerTest < ActiveSupport::TestCase
    setup do
      @product = Product.create!(
        source_product_id: "TEST-1",
        title: "Test Shoe",
        vendor: "Nike",
        product_type: "Shoes",
        status: "active",
        shopify_id: "999"
      )

      @variant = @product.product_variants.create!(
        source_variant_id: "TEST-1-W-42",
        title: "White / 42",
        color: "White",
        size: "42",
        sku: "TEST-SKU-42",
        price: 99.00,
        inventory_quantity: 5
      )

      @client = Minitest::Mock.new
      @syncer = ProductVariantSyncer.new
      @syncer.instance_variable_set(:@client, @client)
    end

    test "sync creates options and variants when shopify product has no options" do
      product_response = {
        "data" => {
          "product" => {
            "id" => "gid://shopify/Product/999",
            "options" => [],
            "variants" => {
              "nodes" => [
                { "id" => "gid://shopify/ProductVariant/1", "title" => "Default Title", "sku" => nil, "inventoryItem" => { "id" => "gid://shopify/InventoryItem/1" }, "selectedOptions" => [] }
              ]
            }
          }
        }
      }

      options_response = {
        "data" => {
          "productOptionsCreate" => {
            "userErrors" => [],
            "product" => { "id" => "gid://shopify/Product/999", "options" => [] }
          }
        }
      }

      create_response = {
        "data" => {
          "productVariantsBulkCreate" => {
            "userErrors" => [],
            "productVariants" => [
              {
                "id" => "gid://shopify/ProductVariant/2",
                "sku" => "TEST-SKU-42",
                "inventoryItem" => { "id" => "gid://shopify/InventoryItem/2" }
              }
            ]
          }
        }
      }

      product_with_options = {
        "data" => {
          "product" => {
            "id" => "gid://shopify/Product/999",
            "options" => [
              { "id" => "gid://shopify/ProductOption/1", "name" => "Color", "optionValues" => [] },
              { "id" => "gid://shopify/ProductOption/2", "name" => "Size", "optionValues" => [] }
            ],
            "variants" => {
              "nodes" => [
                { "id" => "gid://shopify/ProductVariant/1", "title" => "Default Title", "sku" => nil, "inventoryItem" => { "id" => "gid://shopify/InventoryItem/1" }, "selectedOptions" => [] }
              ]
            }
          }
        }
      }

      update_response = {
        "data" => {
          "productVariantsBulkUpdate" => {
            "userErrors" => [],
            "productVariants" => []
          }
        }
      }

      @client.expect(:query, product_response, [ ProductVariantSyncer::GET_PRODUCT, Hash ])
      @client.expect(:query, options_response, [ ProductVariantSyncer::OPTIONS_CREATE, Hash ])
      @client.expect(:query, product_with_options, [ ProductVariantSyncer::GET_PRODUCT, Hash ])
      @client.expect(:query, create_response, [ String, Hash ])
      @client.expect(:query, product_with_options, [ ProductVariantSyncer::GET_PRODUCT, Hash ])
      @client.expect(:query, update_response, [ ProductVariantSyncer::BULK_UPDATE, Hash ])
      @client.expect(:query, { "data" => { "locations" => { "nodes" => [] } } }, [ ProductVariantSyncer::GET_LOCATIONS ])

      with_env("SHOPIFY_LOCATION_ID" => nil) do
        @syncer.sync(@product)
      end

      @variant.reload
      assert_equal "2", @variant.shopify_id
      @client.verify
    end

    private

    def with_env(vars)
      old = vars.keys.index_with { |key| ENV[key] }
      vars.each { |key, value| ENV[key] = value }
      yield
    ensure
      old.each do |key, value|
        if value.nil?
          ENV.delete(key)
        else
          ENV[key] = value
        end
      end
    end
  end
end
