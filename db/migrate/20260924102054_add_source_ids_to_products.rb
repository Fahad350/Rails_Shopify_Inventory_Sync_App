class AddSourceIdsToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :source_product_id, :string
    add_column :product_variants, :source_variant_id, :string

    add_index :products, :source_product_id, unique: true
    add_index :product_variants, :source_variant_id, unique: true
  end
end