class OrderItem < ApplicationRecord
  belongs_to :order, inverse_of: :order_items
  belongs_to :product, inverse_of: :order_items
  has_one :review, inverse_of: :order_item

  validates :product_name, :product_sku, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price, :total_price, numericality: { greater_than_or_equal_to: 0 }
  validate :total_matches_unit_price

  # Builds the immutable purchase record from the live catalogue. Called once,
  # inside the checkout transaction, after the price has been re-read under the
  # inventory lock (see ADR-005 for why these are copies rather than a join).
  def self.snapshot_from(product:, quantity:)
    new(
      product: product,
      product_name: product.name,
      product_sku: product.sku,
      unit_price: product.price,
      quantity: quantity,
      total_price: (product.price * quantity).round(2)
    )
  end

  private

  def total_matches_unit_price
    return if unit_price.nil? || quantity.nil? || total_price.nil?
    return if total_price == (unit_price * quantity).round(2)

    errors.add(:total_price, :does_not_match_unit_price)
  end
end
