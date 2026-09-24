require "csv"

class SupplierCsvImporter
  FILE_PATH = Rails.root.join("data", "supplier_products.csv")

  def self.call
    new.call
  end

  def call
    CSV.foreach(FILE_PATH, headers: true) do |row|
      import_row(row)
    end
  end

  private

  def import_row(row)
    product = Product.find_or_initialize_by(
      source_product_id: row["source_product_id"]
    )

    product.assign_attributes(
      title: row["title"],
      vendor: row["vendor"],
      product_type: row["product_type"],
      status: row["status"]
    )

    product.save!

    variant = product.product_variants.find_or_initialize_by(
      source_variant_id: row["source_variant_id"]
    )

    variant.assign_attributes(
      title: row["variant_title"],
      sku: row["sku"],
      price: row["price"],
      inventory_quantity: row["inventory_quantity"]
    )

    variant.save!
  end
end