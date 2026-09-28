class Order < ApplicationRecord
  STATUSES = %w[pending paid processing shipped delivered cancelled refunded].freeze

  # Statuses a customer may cancel from. Once an order ships, cancellation
  # becomes a return, which is a different workflow with different accounting.
  CANCELLABLE_STATUSES = %w[pending paid processing].freeze

  belongs_to :user, inverse_of: :orders
  belongs_to :coupon, optional: true, inverse_of: :orders
  has_many :order_items, inverse_of: :order
  has_many :payments, inverse_of: :order

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :number, :idempotency_key, presence: true
  validates :number, :idempotency_key, uniqueness: { case_sensitive: false }
  validates :shipping_address, presence: true
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :subtotal_amount, :discount_amount, :tax_amount,
            :shipping_amount, :total_amount,
            numericality: { greater_than_or_equal_to: 0 }

  # Mirrors the CHECK constraint so a bad total is reported as a validation
  # error rather than surfacing as a StatementInvalid from the database.
  validate :total_matches_components

  scope :recent_first, -> { order(created_at: :desc) }
  # Order detail and history endpoints must use this: without it, rendering a
  # list of orders queries line items and their products once per order.
  scope :with_detail_associations, -> { includes(order_items: :product, payments: []) }

  def cancellable?
    CANCELLABLE_STATUSES.include?(status)
  end

  def calculated_total
    subtotal_amount - discount_amount + tax_amount + shipping_amount
  end

  # The payment that currently represents this order's money. Payments are
  # append-only — a retry creates a new row rather than mutating the failed
  # one — so the latest is the authoritative one.
  def current_payment
    payments.max_by(&:created_at)
  end

  private

  def total_matches_components
    return if total_amount.nil? || total_amount == calculated_total

    errors.add(:total_amount, :does_not_match_components)
  end
end
