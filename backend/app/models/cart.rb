class Cart < ApplicationRecord
  STATUSES = %w[active converted abandoned].freeze

  belongs_to :user, inverse_of: :carts
  has_many :cart_items, inverse_of: :cart

  enum :status, STATUSES.index_with(&:itself), validate: true

  scope :with_pricing_associations, -> { includes(cart_items: { product: :inventory }) }

  # Line subtotal only. The authoritative order total — discount, tax and
  # shipping included — is calculated server-side during checkout and stored on
  # the order, because a cart total computed at display time would drift from
  # what the customer is actually charged.
  def items_subtotal
    cart_items.sum { |item| item.unit_price * item.quantity }
  end

  def empty?
    cart_items.empty?
  end
end
