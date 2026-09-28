class AddColorAndSizeToProductVariants < ActiveRecord::Migration[8.1]
  def change
    add_column :product_variants, :color, :string
    add_column :product_variants, :size, :string
  end
end
