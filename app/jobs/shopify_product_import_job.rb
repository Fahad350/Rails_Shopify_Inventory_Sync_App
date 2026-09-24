class ShopifyProductImportJob < ApplicationJob
  queue_as :default

  def perform
    Shopify::ProductImporter.new.call
  end
end
