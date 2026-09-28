class CreateReviews < ActiveRecord::Migration[8.1]
  REVIEW_STATUSES = %w[pending approved rejected].freeze

  def change
    create_table :reviews do |t|
      # index: false because the unique (user_id, product_id) index below covers
      # user_id from its leading column.
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      # Keeps its own index: the partial approved-only index below cannot serve
      # queries that span all statuses, such as admin moderation queues.
      t.references :product, null: false, foreign_key: { on_delete: :cascade }
      # Links a review to the specific purchase that entitles it, which is what
      # makes a "verified purchase" badge truthful. Nullable so an administrator
      # can still curate a review whose order was later removed, and nullify
      # rather than cascade so deleting order history does not silently delete
      # customer-authored content.
      t.references :order_item, foreign_key: { on_delete: :nullify }

      t.integer :rating, null: false
      t.string :title
      t.text :body

      # Reviews are user-generated content reaching a public page, so they are
      # moderated by default rather than published on write.
      t.string :status, null: false, default: "pending"

      t.timestamps

      t.check_constraint "status IN (#{quoted(REVIEW_STATUSES)})", name: "reviews_status_check"

      # A 1-5 scale. Enforced in the database because the average rating is
      # computed with SQL aggregation: a single out-of-range row would skew a
      # product's score with no validation ever running.
      t.check_constraint "rating BETWEEN 1 AND 5", name: "reviews_rating_range_check"

      # One review per product per customer. Prevents both accidental double
      # submission and deliberate rating inflation.
      t.index %i[user_id product_id], unique: true

      # The product detail page reads approved reviews newest-first, and the
      # rating summary aggregates the same partial set. Partial on approved
      # because pending and rejected reviews are never shown publicly, so
      # indexing them would add write cost for rows the hot query excludes.
      t.index %i[product_id created_at], order: { created_at: :desc },
              where: "status = 'approved'",
              name: "index_reviews_on_approved_product_recency"
    end
  end

  private

  def quoted(values)
    values.map { |value| "'#{value}'" }.join(", ")
  end
end
