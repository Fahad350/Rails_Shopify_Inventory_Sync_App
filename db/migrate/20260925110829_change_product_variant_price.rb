class ChangeProductVariantPrice < ActiveRecord::Migration[8.1]
  def change
    change_column :product_variants, :price,
                  :decimal,
                  precision: 10,
                  scale: 2
  end
end