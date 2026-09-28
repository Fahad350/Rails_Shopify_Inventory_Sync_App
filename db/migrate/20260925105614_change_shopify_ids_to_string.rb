class ChangeShopifyIdsToString < ActiveRecord::Migration[8.1]
  def change
    change_column :products, :shopify_id, :string
    change_column :product_variants, :shopify_id, :string
  end
end
