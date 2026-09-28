class Category < ApplicationRecord
  belongs_to :parent, class_name: "Category", optional: true, inverse_of: :children
  has_many :children, class_name: "Category", foreign_key: :parent_id, inverse_of: :parent
  has_many :products, inverse_of: :category

  normalizes :slug, with: ->(slug) { slug.to_s.strip.downcase }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { case_sensitive: false },
                   format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: :invalid_slug }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # A category cannot be its own parent. Deeper cycles (A -> B -> A) are not
  # prevented here: detecting them needs a recursive query, and the admin UI
  # only ever offers a flat parent list. If arbitrary re-parenting is exposed,
  # this becomes a recursive CTE check rather than a Ruby one.
  validate :parent_is_not_self

  scope :roots, -> { where(parent_id: nil) }
  scope :ordered, -> { order(:position, :name) }

  def to_param = slug

  private

  def parent_is_not_self
    errors.add(:parent_id, :cannot_be_self) if persisted? && parent_id == id
  end
end
