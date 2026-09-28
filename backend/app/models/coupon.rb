class Coupon < ApplicationRecord
  DISCOUNT_TYPES = %w[percentage fixed_amount].freeze

  has_many :orders, inverse_of: :coupon

  enum :discount_type, DISCOUNT_TYPES.index_with(&:itself), validate: true

  normalizes :code, with: ->(code) { code.to_s.strip.upcase }

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :discount_value, numericality: { greater_than: 0 }
  validates :discount_value, numericality: { less_than_or_equal_to: 100 }, if: :percentage?
  validates :minimum_order_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :maximum_discount_amount, numericality: { greater_than: 0 }, allow_nil: true
  validates :usage_limit, :usage_limit_per_user,
            numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :expiry_follows_start

  scope :usable, lambda { |at = Time.current|
    where(active: true)
      .where("starts_at IS NULL OR starts_at <= ?", at)
      .where("expires_at IS NULL OR expires_at > ?", at)
  }

  # Whether the coupon itself is usable, independent of any particular cart.
  # Cart-specific eligibility — minimum order value, per-user limits — is
  # decided by ApplyCoupon during checkout, where the cart is known and the
  # redemption can be recorded in the same transaction.
  def redeemable?(at: Time.current)
    active? &&
      (starts_at.nil? || starts_at <= at) &&
      (expires_at.nil? || expires_at > at) &&
      (usage_limit.nil? || times_used < usage_limit)
  end

  # Pure calculation, no persistence, so it is trivially testable against the
  # rounding rules that matter for money.
  def discount_for(subtotal)
    raw = percentage? ? subtotal * discount_value / 100 : discount_value
    raw = [ raw, maximum_discount_amount ].min if maximum_discount_amount.present?
    # Never discount more than the subtotal: the orders table has a CHECK that
    # would reject it, and a negative total is meaningless.
    [ raw, subtotal ].min.round(2)
  end

  private

  def expiry_follows_start
    return if starts_at.blank? || expires_at.blank? || expires_at > starts_at

    errors.add(:expires_at, :must_follow_start)
  end
end
