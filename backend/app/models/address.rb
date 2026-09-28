class Address < ApplicationRecord
  KINDS = %w[shipping billing].freeze

  belongs_to :user, inverse_of: :addresses

  enum :kind, KINDS.index_with(&:itself), validate: true

  normalizes :country_code, with: ->(code) { code.to_s.strip.upcase }

  validates :recipient_name, :line1, :city, :postal_code, presence: true
  validates :country_code, presence: true, format: { with: /\A[A-Z]{2}\z/ }

  scope :defaults, -> { where(is_default: true) }

  # Written as a snapshot onto an order at checkout. Orders must not reference
  # addresses, because an address can be edited after the order ships
  # (see ADR-005).
  def to_snapshot
    slice(
      "recipient_name", "line1", "line2", "city",
      "region", "postal_code", "country_code", "phone"
    ).compact
  end
end
