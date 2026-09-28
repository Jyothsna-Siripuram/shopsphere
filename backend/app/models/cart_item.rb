class CartItem < ApplicationRecord
  belongs_to :cart, inverse_of: :cart_items
  belongs_to :product, inverse_of: false

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :product_id, uniqueness: { scope: :cart_id }

  # Live catalogue price, deliberately not stored.
  #
  # A cart shows the current price; an order stores the price at purchase. If
  # a cart cached the price, a customer could hold a stale cheaper price
  # indefinitely. Checkout re-reads it from the product inside the transaction,
  # which is also what makes the stored order price trustworthy.
  def unit_price
    product.price
  end

  def line_total
    unit_price * quantity
  end
end
