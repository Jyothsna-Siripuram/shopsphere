class CreateCatalogue < ActiveRecord::Migration[8.1]
  PRODUCT_STATUSES = %w[draft active archived].freeze

  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.citext :slug, null: false
      t.text :description
      # Self-referential hierarchy. Nullify rather than cascade: deleting a
      # parent must not silently delete an entire subtree of categories.
      t.references :parent, foreign_key: { to_table: :categories, on_delete: :nullify }
      t.integer :position, null: false, default: 0

      t.timestamps

      # Categories are addressed by slug in URLs (/categories/mens-footwear),
      # so every catalogue page load resolves one. Unique because two
      # categories sharing a slug makes the route ambiguous.
      t.index :slug, unique: true
    end

    create_table :products do |t|
      t.string :name, null: false
      t.citext :slug, null: false
      t.text :description
      t.citext :sku, null: false
      # Restrict: a category with products must be emptied or reassigned before
      # it can be deleted. Cascade here would silently destroy catalogue data.
      # index: false because (category_id, status) below covers category_id.
      t.references :category, null: false, index: false, foreign_key: { on_delete: :restrict }
      t.decimal :price, precision: 12, scale: 2, null: false
      # Optional "was" price for showing a markdown. Nullable because most
      # products are not discounted.
      t.decimal :compare_at_price, precision: 12, scale: 2
      t.string :status, null: false, default: "draft"
      t.integer :weight_grams
      t.datetime :published_at

      t.timestamps

      t.index :slug, unique: true
      t.index :sku, unique: true

      t.check_constraint "status IN (#{quoted(PRODUCT_STATUSES)})", name: "products_status_check"
      # Money is never negative. Enforced here because a negative price would
      # invert every total downstream, and a validation-only guard is bypassed
      # by update_all, raw SQL, and the console.
      t.check_constraint "price >= 0", name: "products_price_non_negative_check"
      t.check_constraint "compare_at_price IS NULL OR compare_at_price >= 0",
                         name: "products_compare_at_price_non_negative_check"
      t.check_constraint "weight_grams IS NULL OR weight_grams >= 0",
                         name: "products_weight_non_negative_check"

      # The catalogue listing query is
      #   WHERE status = 'active' ORDER BY published_at DESC LIMIT n
      # and it runs on nearly every page view. A composite index lets Postgres
      # satisfy both the filter and the sort from one index scan, avoiding a
      # sort of the whole active set.
      #
      # Partial (WHERE status = 'active') because draft and archived rows are
      # never listed, so indexing them is pure write and storage cost.
      # Trade-off: publishing or archiving a product rewrites this index entry,
      # which is cheap relative to how often the read runs.
      t.index %i[status published_at], order: { published_at: :desc },
              where: "status = 'active'",
              name: "index_products_on_active_published_at"

      # Admin and storefront both browse "products in this category". Composite
      # with status so the filter is index-only rather than a filter-after-scan.
      t.index %i[category_id status]
    end

    create_table :product_images do |t|
      # index: false because (product_id, position) below covers product_id.
      t.references :product, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :storage_key, null: false
      t.string :alt_text
      t.integer :position, null: false, default: 0
      t.boolean :is_primary, null: false, default: false

      t.timestamps

      t.check_constraint "position >= 0", name: "product_images_position_non_negative_check"

      # A product renders its images in order; a listing renders only the
      # primary one.
      t.index %i[product_id position]

      # Exactly one primary image per product, guaranteed against two concurrent
      # admin updates both promoting a different image.
      t.index :product_id, unique: true, where: "is_primary",
              name: "index_product_images_on_one_primary_per_product"
    end

    # Stock lives in its own table rather than as a products.stock column.
    #
    # Checkout takes an exclusive row lock on stock (SELECT ... FOR UPDATE).
    # If that value lived on products, the lock would cover the whole product
    # row, so an administrator editing a description would block checkout and
    # checkout would block catalogue writes. Separating them means the lock
    # covers only the contended quantity.
    #
    # It also keeps the hot, frequently-updated row narrow: a purchase rewrites
    # a small inventories row instead of a wide products row, which produces
    # less write amplification and less vacuum pressure.
    create_table :inventories do |t|
      t.references :product, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.integer :available_quantity, null: false, default: 0
      t.integer :reorder_threshold, null: false, default: 0

      t.timestamps

      # THE oversell backstop.
      #
      # Checkout prevents overselling by locking the row and checking
      # availability before decrementing. That mechanism lives in application
      # code and can be forgotten by a future job, an admin bulk edit, or a
      # console session. This constraint makes overselling impossible at the
      # storage layer regardless: any statement that would drive stock below
      # zero raises instead of succeeding quietly.
      #
      # Mechanisms get forgotten. Constraints do not.
      t.check_constraint "available_quantity >= 0",
                         name: "inventories_available_quantity_non_negative_check"
      t.check_constraint "reorder_threshold >= 0",
                         name: "inventories_reorder_threshold_non_negative_check"

      # Powers the admin low-stock dashboard:
      #   WHERE available_quantity <= reorder_threshold
      # Partial indexes cannot reference two columns in their predicate, so this
      # indexes the quantity and lets Postgres filter the comparison. Kept
      # narrow because the dashboard is an infrequent admin read; the write cost
      # of a wider index is not justified by it.
      t.index :available_quantity
    end
  end

  private

  def quoted(values)
    values.map { |value| "'#{value}'" }.join(", ")
  end
end
