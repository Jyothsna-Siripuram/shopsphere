class ProductImage < ApplicationRecord
  belongs_to :product, inverse_of: :product_images

  validates :storage_key, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :primary, -> { where(is_primary: true) }
end
