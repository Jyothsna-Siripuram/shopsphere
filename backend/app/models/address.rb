class Address < ApplicationRecord
  KINDS = %w[shipping billing].freeze

  belongs_to :user, inverse_of: :addresses

  enum :kind, KINDS.index_with(&:itself), validate: true

  normalizes :country_code, with: ->(code) { code.to_s.strip.upcase }

  validates :recipient_name, :line1, :city, :postal_code, presence: true
  validates :country_code, presence: true, format: { with: /\A[A-Z]{2}\z/ }

  # Marking an address default demotes the previous one.
  #
  # Without this, the partial unique index (user_id, kind) WHERE is_default
  # rejected the write with a raw PG::UniqueViolation, so a customer setting a
  # new default address received a 500. "Make this my default" is a request to
  # move the flag, not to create a second one.
  #
  # A callback rather than a service object because the invariant must hold from
  # every entry point — controller, console, a future admin tool — and Rails
  # wraps save in a transaction, so the demotion and the write commit together.
  #
  # It does not close the concurrent case: two simultaneous requests can each
  # demote rows the other has not yet committed and both insert. The unique
  # index still refuses, and ApplicationController maps that to 409 Conflict
  # rather than a 500.
  before_save :demote_sibling_defaults, if: :claiming_default?

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

  private

  def claiming_default?
    is_default? && (new_record? || will_save_change_to_is_default? || will_save_change_to_kind?)
  end

  def demote_sibling_defaults
    scope = Address.where(user_id: user_id, kind: kind, is_default: true)
    scope = scope.where.not(id: id) if persisted?

    scope.update_all(is_default: false, updated_at: Time.current)
  end
end
