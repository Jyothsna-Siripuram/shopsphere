class Cart < ApplicationRecord
  STATUSES = %w[active converted abandoned].freeze

  belongs_to :user, inverse_of: :carts
  # Ordered so a cart renders its lines in the order they were added, with id
  # as the tiebreaker for lines added in the same instant.
  has_many :cart_items, -> { order(:created_at, :id) }, inverse_of: :cart

  enum :status, STATUSES.index_with(&:itself), validate: true

  # Everything the cart serializer reads: price and stock to judge each line,
  # images to draw it. Without product_images the cart would N+1 on
  # Product#primary_image.
  scope :with_pricing_associations,
        -> { includes(cart_items: { product: %i[inventory product_images] }) }

  # The caller's active cart, creating it if there is none.
  #
  # Find first: the cart almost always exists, and create_or_find_by! would
  # otherwise attempt an INSERT — and burn a sequence value — on every call.
  #
  # Then create_or_find_by!, not find_or_create_by!. Two concurrent first
  # "add to cart" requests would both find nothing and both INSERT. The partial
  # unique index (one active cart per user) refuses the second, and
  # create_or_find_by! answers that refusal by reading the winner's row, so
  # both requests land in the same cart instead of one failing with a 409.
  def self.find_or_create_active_for!(user)
    active.find_by(user: user) || active.create_or_find_by!(user: user)
  end

  # Line subtotal only. The authoritative order total — discount, tax and
  # shipping included — is calculated server-side during checkout and stored on
  # the order, because a cart total computed at display time would drift from
  # what the customer is actually charged.
  def items_subtotal
    cart_items.sum { |item| item.unit_price * item.quantity }
  end

  def item_count
    cart_items.sum(&:quantity)
  end

  def empty?
    cart_items.empty?
  end

  # Whether every line could be bought right now. A hint for the client, not a
  # guarantee: stock can change before checkout, which re-checks under lock
  # (ADR-001).
  def checkout_ready?
    !empty? && cart_items.all?(&:available?)
  end
end
