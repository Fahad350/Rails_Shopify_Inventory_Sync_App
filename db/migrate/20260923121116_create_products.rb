class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.bigint :shopify_id
      t.string :title
      t.string :vendor
      t.string :product_type
      t.string :status

      t.timestamps
    end
  end
end
