class CreateCoupons < ActiveRecord::Migration[8.1]
  DISCOUNT_TYPES = %w[percentage fixed_amount].freeze

  def change
    create_table :coupons do |t|
      t.citext :code, null: false
      t.string :description
      t.string :discount_type, null: false
      t.decimal :discount_value, precision: 12, scale: 2, null: false
      t.decimal :minimum_order_amount, precision: 12, scale: 2, null: false, default: 0
      # Caps a percentage discount ("20% off, up to $50"). Null means uncapped.
      t.decimal :maximum_discount_amount, precision: 12, scale: 2
      # Null means unlimited.
      t.integer :usage_limit
      t.integer :usage_limit_per_user
      t.integer :times_used, null: false, default: 0
      t.datetime :starts_at
      t.datetime :expires_at
      t.boolean :active, null: false, default: true

      t.timestamps

      # Customers type coupon codes; citext means "SAVE20" and "save20" are the
      # same coupon rather than a confusing near-miss.
      t.index :code, unique: true

      t.check_constraint "discount_type IN (#{quoted(DISCOUNT_TYPES)})",
                         name: "coupons_discount_type_check"
      t.check_constraint "discount_value > 0", name: "coupons_discount_value_positive_check"
      t.check_constraint "minimum_order_amount >= 0",
                         name: "coupons_minimum_order_amount_non_negative_check"
      t.check_constraint "times_used >= 0", name: "coupons_times_used_non_negative_check"
      t.check_constraint "usage_limit IS NULL OR usage_limit > 0",
                         name: "coupons_usage_limit_positive_check"
      t.check_constraint "usage_limit_per_user IS NULL OR usage_limit_per_user > 0",
                         name: "coupons_usage_limit_per_user_positive_check"

      # A percentage discount above 100 would pay the customer to order.
      t.check_constraint(
        "discount_type <> 'percentage' OR discount_value <= 100",
        name: "coupons_percentage_within_bounds_check"
      )

      # A validity window that closes before it opens can never match, so it is
      # always an authoring mistake. Catching it at write time beats debugging
      # "why does my coupon never apply" later.
      t.check_constraint(
        "starts_at IS NULL OR expires_at IS NULL OR expires_at > starts_at",
        name: "coupons_validity_window_check"
      )

      # Admin listing of currently-valid coupons filters on active plus the
      # window. Narrow partial index: expired and disabled coupons accumulate
      # forever and are never in the hot path.
      t.index :expires_at, where: "active", name: "index_coupons_on_active_expiry"
    end
  end

  private

  def quoted(values)
    values.map { |value| "'#{value}'" }.join(", ")
  end
end
