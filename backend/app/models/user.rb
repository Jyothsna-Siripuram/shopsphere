class User < ApplicationRecord
  ROLES = %w[customer admin].freeze
  STATUSES = %w[active suspended].freeze

  has_secure_password

  has_many :addresses, inverse_of: :user
  has_many :carts, inverse_of: :user
  has_many :orders, inverse_of: :user
  has_many :reviews, inverse_of: :user
  has_one :wishlist, inverse_of: :user

  # The one active cart, matching the partial unique index that guarantees
  # there can only be one.
  has_one :active_cart, -> { where(status: :active) },
          class_name: "Cart", inverse_of: :user

  enum :role, ROLES.index_with(&:itself), validate: true
  # suffix avoids colliding with the role predicates and reads better:
  # user.active_status? rather than an ambiguous user.active?
  enum :status, STATUSES.index_with(&:itself), validate: true, suffix: :status

  # Stored lowercase so the value displayed back matches what uniqueness
  # compares. The citext column already makes the unique index
  # case-insensitive; this keeps the stored form canonical too.
  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  # has_secure_password enforces presence and confirmation; length is ours.
  # The maximum exists because bcrypt silently truncates beyond 72 bytes, so a
  # longer password would give a false sense of strength.
  validates :password, length: { minimum: 12, maximum: 72 }, allow_nil: true

  # The single authorization predicate.
  #
  # Every Pundit policy asks this, never `user.role == "admin"`. If roles ever
  # become a table (see ADR-004), only this method changes.
  def admin?
    role == "admin"
  end

  def full_name
    [ first_name, last_name ].compact_blank.join(" ").presence
  end
end
