class Payment < ApplicationRecord
  STATUSES = %w[pending authorized captured failed refunded].freeze

  belongs_to :order, inverse_of: :payments

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :idempotency_key, presence: true, uniqueness: { case_sensitive: false }
  validates :provider, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :provider_reference, uniqueness: { case_sensitive: false }, allow_nil: true
  # Mirrors the CHECK that keeps the audit trail honest: a failure explains
  # itself, a success does not claim a reason.
  validates :failure_reason, presence: true, if: :failed?
  validates :failure_reason, absence: true, unless: :failed?

  scope :successful, -> { where(status: :captured) }

  def settled?
    captured? || refunded?
  end
end
