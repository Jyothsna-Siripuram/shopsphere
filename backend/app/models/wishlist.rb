class Wishlist < ApplicationRecord
  belongs_to :user, inverse_of: :wishlist
  has_many :wishlist_items, inverse_of: :wishlist
  has_many :products, through: :wishlist_items

  def includes_product?(product)
    wishlist_items.exists?(product_id: product.id)
  end
end
