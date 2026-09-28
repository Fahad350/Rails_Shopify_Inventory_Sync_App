class ProductVariant < ApplicationRecord
  belongs_to :product

  validates :source_variant_id, uniqueness: true, allow_nil: true
  validates :sku, presence: true, if: -> { source_variant_id.present? }
  validates :color, :size, presence: true, if: -> { source_variant_id.present? }

  scope :from_supplier, -> { where.not(source_variant_id: [ nil, "" ]) }
  scope :needs_shopify_create, -> { from_supplier.where(shopify_id: nil) }
  scope :linked_to_shopify, -> { where.not(shopify_id: nil) }

  def from_supplier?
    source_variant_id.present?
  end

  def configurable?
    from_supplier? && color.present? && size.present?
  end
end
