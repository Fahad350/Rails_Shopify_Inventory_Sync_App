class Product < ApplicationRecord
  has_many :product_variants, dependent: :destroy

  scope :from_supplier, -> { where.not(source_product_id: [ nil, "" ]) }

  def from_supplier?
    source_product_id.present?
  end

  def supplier_variants
    product_variants.select(&:from_supplier?)
  end
end
