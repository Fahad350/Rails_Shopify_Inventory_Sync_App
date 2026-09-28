
module Shopify
  class ProductSyncer

    CREATE_MUTATION = <<~GRAPHQL
      mutation ProductCreate($product: ProductCreateInput!) {
        productCreate(product: $product) {
          product {
            id
            title
            handle
            status
          }

          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    UPDATE_MUTATION = <<~GRAPHQL
      mutation UpdateProduct($input: ProductUpdateInput!) {
        productUpdate(product: $input) {
          product {
            id
            title
            vendor
            productType
            status
          }

          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    def initialize
      @client = Shopify::Client.new
    end

    # Create a new product in Shopify
    def create(product)
      response = @client.query(
        CREATE_MUTATION,
        {
          product: {
            title: product.title,
            vendor: product.vendor,
            productType: product.product_type,
            status: product.status.upcase
          }
        }
      )

      result = response.dig("data", "productCreate")

      unless result
        raise "Shopify productCreate returned no result: #{response.inspect}"
      end

      if result["userErrors"].any?
        raise result["userErrors"].inspect
      end

      shopify_product = result["product"]

      shopify_id = shopify_product["id"].split("/").last

      product.update!(
        shopify_id: shopify_id
      )

      shopify_product
    end

    # Update an existing product in Shopify
    def update(product)
      response = @client.query(
        UPDATE_MUTATION,
        {
          input: {
            id: "gid://shopify/Product/#{product.shopify_id}",
            title: product.title,
            vendor: product.vendor,
            productType: product.product_type,
            status: product.status.upcase
          }
        }
      )

      result = response.dig("data", "productUpdate")

      unless result
        raise "Shopify productUpdate returned no result: #{response.inspect}"
      end

      if result["userErrors"].any?
        raise result["userErrors"].inspect
      end

      result["product"]
    end

  end
end
