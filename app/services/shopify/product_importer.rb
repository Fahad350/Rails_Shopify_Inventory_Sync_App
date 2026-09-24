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

            variants(first: 50) {
              nodes {
                id
                title
                sku
                price
                inventoryQuantity
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
        product = Product.find_or_initialize_by(
          shopify_id: shopify_product["id"].split("/").last
        )

        product.update!(
          title: shopify_product["title"],
          vendor: shopify_product["vendor"],
          product_type: shopify_product["productType"],
          status: shopify_product["status"]
        )

        variants = shopify_product.dig("variants", "nodes") || []

        variants.each do |shopify_variant|
          ProductVariant.find_or_initialize_by(
            shopify_id: shopify_variant["id"].split("/").last
          ).update!(
            product: product,
            title: shopify_variant["title"],
            sku: shopify_variant["sku"],
            price: shopify_variant["price"],
            inventory_quantity: shopify_variant["inventoryQuantity"]
          )
        end
      end
    end
  end
end