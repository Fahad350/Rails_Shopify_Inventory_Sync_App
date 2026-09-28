class SyncProductsJob < ApplicationJob
  queue_as :default

  def perform
    stats = { synced: 0, skipped: 0, failed: 0 }

    Product.from_supplier.find_each do |product|
      sync_product(product)
      stats[:synced] += 1
    rescue StandardError => e
      stats[:failed] += 1
      Rails.logger.error(
        "[SyncProductsJob] product_id=#{product.id} source_product_id=#{product.source_product_id} " \
        "#{e.class}: #{e.message}"
      )
    end

    skipped = Product.where(source_product_id: [ nil, "" ]).count
    stats[:skipped] = skipped

    Rails.logger.info("[SyncProductsJob] finished #{stats.inspect}")
    stats
  end

  private

  def sync_product(product)
    product_syncer = Shopify::ProductSyncer.new
    variant_syncer = Shopify::ProductVariantSyncer.new

    if product.shopify_id.present?
      product_syncer.update(product)
    else
      product_syncer.create(product)
    end

    variant_syncer.sync(product)
  end
end
