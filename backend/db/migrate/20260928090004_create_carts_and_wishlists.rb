class CreateCartsAndWishlists < ActiveRecord::Migration[8.1]
  CART_STATUSES = %w[active converted abandoned].freeze

  def change
    create_table :carts do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :status, null: false, default: "active"

      t.timestamps

      t.check_constraint "status IN (#{quoted(CART_STATUSES)})", name: "carts_status_check"

      # A user has at most one active cart, but keeps converted carts as
      # history. A plain unique index on user_id would forbid the history; a
      # partial unique index expresses exactly the real rule.
      #
      # This also closes a race: two concurrent "add to cart" requests from the
      # same user, each finding no cart and creating one, would otherwise leave
      # the account with two active carts and items silently split between them.
      t.index :user_id, unique: true, where: "status = 'active'",
              name: "index_carts_on_one_active_per_user"
    end

    create_table :cart_items do |t|
      # index: false because the unique (cart_id, product_id) index below covers
      # cart_id from its leading column.
      t.references :cart, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: { on_delete: :cascade }
      t.integer :quantity, null: false

      t.timestamps

      # Strictly positive: a zero-quantity line is a removal, not a line item,
      # and a negative one would subtract from the order total.
      t.check_constraint "quantity > 0", name: "cart_items_quantity_positive_check"

      # One line per product per cart. Adding an existing product increments the
      # quantity instead of creating a second line, and this makes that an
      # enforced invariant rather than a convention two concurrent requests can
      # break.
      t.index %i[cart_id product_id], unique: true
    end

    create_table :wishlists do |t|
      # One wishlist per user, enforced by a unique index on the FK.
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }

      t.timestamps
    end

    create_table :wishlist_items do |t|
      # index: false because the unique (wishlist_id, product_id) index below
      # covers wishlist_id from its leading column.
      t.references :wishlist, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps

      # Saving the same product twice is a no-op, not a duplicate row.
      t.index %i[wishlist_id product_id], unique: true
    end
  end

  private

  def quoted(values)
    values.map { |value| "'#{value}'" }.join(", ")
  end
end
