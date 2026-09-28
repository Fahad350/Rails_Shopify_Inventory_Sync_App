require "test_helper"

class SyncProductsJobTest < ActiveSupport::TestCase
  test "perform syncs only supplier products" do
    Product.create!(
      shopify_id: "111",
      title: "Shopify Dummy",
      vendor: "Test",
      product_type: "Shoes",
      status: "active"
    )

    supplier_product = Product.create!(
      source_product_id: "NIKE-1",
      title: "Supplier Shoe",
      vendor: "Nike",
      product_type: "Shoes",
      status: "active"
    )

    product_syncer = Minitest::Mock.new
    product_syncer.expect(:create, true, [ supplier_product ])

    variant_syncer = Minitest::Mock.new
    variant_syncer.expect(:sync, true, [ supplier_product ])

    Shopify::ProductSyncer.stub(:new, product_syncer) do
      Shopify::ProductVariantSyncer.stub(:new, variant_syncer) do
        stats = SyncProductsJob.perform_now
        assert_equal 1, stats[:synced]
        assert_equal 1, stats[:skipped]
        assert_equal 0, stats[:failed]
      end
    end

    product_syncer.verify
    variant_syncer.verify
  end
end
