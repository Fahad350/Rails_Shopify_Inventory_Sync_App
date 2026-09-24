# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_24_102054) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "product_variants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "inventory_quantity"
    t.decimal "price"
    t.bigint "product_id", null: false
    t.bigint "shopify_id"
    t.string "sku"
    t.string "source_variant_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_product_variants_on_product_id"
    t.index ["source_variant_id"], name: "index_product_variants_on_source_variant_id", unique: true
  end

  create_table "products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "product_type"
    t.bigint "shopify_id"
    t.string "source_product_id"
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "vendor"
    t.index ["source_product_id"], name: "index_products_on_source_product_id", unique: true
  end

  add_foreign_key "product_variants", "products"
end
