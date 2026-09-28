class WishlistItem < ApplicationRecord
  belongs_to :wishlist, inverse_of: :wishlist_items
  belongs_to :product, inverse_of: false

  validates :product_id, uniqueness: { scope: :wishlist_id }
end
