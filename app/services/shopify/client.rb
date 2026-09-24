require "net/http"
require "json"

module Shopify
  class Client
    API_VERSION = "2026-07"

    def initialize
      @shop = ENV.fetch("SHOPIFY_SHOP")
      @access_token = ENV.fetch("SHOPIFY_ADMIN_ACCESS_TOKEN")
    end

   def query(graphql_query, variables = {})
      uri = URI("https://#{@shop}/admin/api/#{API_VERSION}/graphql.json")

      request = Net::HTTP::Post.new(uri)
      request["X-Shopify-Access-Token"] = @access_token
      request["Content-Type"] = "application/json"

      request.body = {
        query: graphql_query,
        variables: variables
      }.to_json

      response = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: true
      ) do |http|
        http.request(request)
      end

      JSON.parse(response.body)
    end
  end
end