class CreateProductVariants < ActiveRecord::Migration[8.1]
  def change
    create_table :product_variants do |t|
      t.bigint :shopify_id
      t.references :product, null: false, foreign_key: true
      t.string :title
      t.string :sku
      t.decimal :price
      t.integer :inventory_quantity

      t.timestamps
    end
  end
end
