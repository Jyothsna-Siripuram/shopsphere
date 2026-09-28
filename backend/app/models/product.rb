class Product < ApplicationRecord
  STATUSES = %w[draft active archived].freeze

  belongs_to :category, inverse_of: :products

  # Images own files in object storage, which the database cannot clean up, so
  # this is one of the two associations that deliberately uses dependent:
  # :destroy rather than the FK cascade (see ApplicationRecord).
  has_many :product_images, -> { order(:position) }, inverse_of: :product, dependent: :destroy
  has_one :inventory, inverse_of: :product
  has_many :order_items, inverse_of: :product
  has_many :reviews, inverse_of: :product

  enum :status, STATUSES.index_with(&:itself), validate: true

  normalizes :slug, with: ->(slug) { slug.to_s.strip.downcase }
  normalizes :sku, with: ->(sku) { sku.to_s.strip.upcase }

  validates :name, :sku, presence: true
  validates :slug, presence: true, uniqueness: { case_sensitive: false },
                   format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: :invalid_slug }
  validates :sku, uniqueness: { case_sensitive: false }
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :compare_at_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :weight_grams, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                           allow_nil: true

  # Matches index_products_on_active_published_at, which is why the order is
  # published_at DESC rather than created_at.
  scope :published, -> { where(status: :active).where.not(published_at: nil) }
  scope :newest_first, -> { order(published_at: :desc) }

  # Every listing endpoint must use this. Without it each product row triggers
  # a separate query for its images and inventory, which is the classic N+1
  # this catalogue would otherwise ship with.
  scope :with_listing_associations, -> { includes(:inventory, :product_images) }

  def to_param = slug

  def primary_image
    product_images.detect(&:is_primary?) || product_images.first
  end

  def purchasable?
    active? && inventory.present? && inventory.in_stock?
  end
end
