class Review < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze

  belongs_to :user, inverse_of: :reviews
  belongs_to :product, inverse_of: :reviews
  # Present when the review is tied to a real purchase, which is what makes a
  # "verified purchase" badge truthful.
  belongs_to :order_item, optional: true, inverse_of: :review

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :rating, numericality: {
    only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5
  }
  validates :user_id, uniqueness: { scope: :product_id }
  validate :order_item_belongs_to_reviewer

  # Matches index_reviews_on_approved_product_recency. Public endpoints must
  # never expose pending or rejected reviews.
  scope :visible, -> { where(status: :approved) }
  scope :recent_first, -> { order(created_at: :desc) }

  def verified_purchase?
    order_item_id.present?
  end

  private

  # Without this, a customer could cite someone else's purchase to earn a
  # verified badge. The check is here rather than in the database because it
  # spans three tables, which a CHECK constraint cannot express.
  def order_item_belongs_to_reviewer
    return if order_item.blank?
    return if order_item.order.user_id == user_id

    errors.add(:order_item, :must_belong_to_reviewer)
  end
end
