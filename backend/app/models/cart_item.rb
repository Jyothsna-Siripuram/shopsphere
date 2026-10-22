class CartItem < ApplicationRecord
  # A per-line ceiling. A business rule rather than an integrity invariant, so
  # it lives here rather than in a CHECK constraint: changing it should be a
  # deploy, not a migration. Carts::AddItem enforces it inside the upsert too,
  # because that path bypasses validations.
  MAX_QUANTITY = 99

  belongs_to :cart, inverse_of: :cart_items
  belongs_to :product, inverse_of: false

  validates :quantity, numericality: { only_integer: true, greater_than: 0,
                                       less_than_or_equal_to: MAX_QUANTITY }
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

  # Why a line can or cannot be bought, without revealing how much stock there
  # is (see ProductSerializer#in_stock). "insufficient_stock" says "fewer than
  # you asked for" — a client can suggest lowering the quantity — but never
  # the number, which would let a competitor read stock levels by probing.
  def availability
    return "unavailable" unless product.published?
    return "out_of_stock" unless product.inventory&.in_stock?
    return "insufficient_stock" unless product.inventory.in_stock?(quantity)

    "available"
  end

  def available?
    availability == "available"
  end
end
