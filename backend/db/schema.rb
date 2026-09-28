# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_28_090007) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "addresses", force: :cascade do |t|
    t.string "city", null: false
    t.string "country_code", limit: 2, null: false
    t.datetime "created_at", null: false
    t.boolean "is_default", default: false, null: false
    t.string "kind", null: false
    t.string "line1", null: false
    t.string "line2"
    t.string "phone"
    t.string "postal_code", null: false
    t.string "recipient_name", null: false
    t.string "region"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "kind"], name: "index_addresses_on_one_default_per_user_and_kind", unique: true, where: "is_default"
    t.index ["user_id"], name: "index_addresses_on_user_id"
    t.check_constraint "country_code::text ~ '^[A-Z]{2}$'::text", name: "addresses_country_code_check"
    t.check_constraint "kind::text = ANY (ARRAY['shipping'::character varying, 'billing'::character varying]::text[])", name: "addresses_kind_check"
  end

  create_table "cart_items", force: :cascade do |t|
    t.bigint "cart_id", null: false
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", null: false
    t.datetime "updated_at", null: false
    t.index ["cart_id", "product_id"], name: "index_cart_items_on_cart_id_and_product_id", unique: true
    t.index ["product_id"], name: "index_cart_items_on_product_id"
    t.check_constraint "quantity > 0", name: "cart_items_quantity_positive_check"
  end

  create_table "carts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_carts_on_one_active_per_user", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["user_id"], name: "index_carts_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'converted'::character varying, 'abandoned'::character varying]::text[])", name: "carts_status_check"
  end

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.bigint "parent_id"
    t.integer "position", default: 0, null: false
    t.citext "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_categories_on_parent_id"
    t.index ["slug"], name: "index_categories_on_slug", unique: true
  end

  create_table "coupons", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.citext "code", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "discount_type", null: false
    t.decimal "discount_value", precision: 12, scale: 2, null: false
    t.datetime "expires_at"
    t.decimal "maximum_discount_amount", precision: 12, scale: 2
    t.decimal "minimum_order_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "starts_at"
    t.integer "times_used", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "usage_limit"
    t.integer "usage_limit_per_user"
    t.index ["code"], name: "index_coupons_on_code", unique: true
    t.index ["expires_at"], name: "index_coupons_on_active_expiry", where: "active"
    t.check_constraint "discount_type::text <> 'percentage'::text OR discount_value <= 100::numeric", name: "coupons_percentage_within_bounds_check"
    t.check_constraint "discount_type::text = ANY (ARRAY['percentage'::character varying, 'fixed_amount'::character varying]::text[])", name: "coupons_discount_type_check"
    t.check_constraint "discount_value > 0::numeric", name: "coupons_discount_value_positive_check"
    t.check_constraint "minimum_order_amount >= 0::numeric", name: "coupons_minimum_order_amount_non_negative_check"
    t.check_constraint "starts_at IS NULL OR expires_at IS NULL OR expires_at > starts_at", name: "coupons_validity_window_check"
    t.check_constraint "times_used >= 0", name: "coupons_times_used_non_negative_check"
    t.check_constraint "usage_limit IS NULL OR usage_limit > 0", name: "coupons_usage_limit_positive_check"
    t.check_constraint "usage_limit_per_user IS NULL OR usage_limit_per_user > 0", name: "coupons_usage_limit_per_user_positive_check"
  end

  create_table "inventories", force: :cascade do |t|
    t.integer "available_quantity", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.integer "reorder_threshold", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["available_quantity"], name: "index_inventories_on_available_quantity"
    t.index ["product_id"], name: "index_inventories_on_product_id", unique: true
    t.check_constraint "available_quantity >= 0", name: "inventories_available_quantity_non_negative_check"
    t.check_constraint "reorder_threshold >= 0", name: "inventories_reorder_threshold_non_negative_check"
  end

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "order_id", null: false
    t.bigint "product_id", null: false
    t.string "product_name", null: false
    t.citext "product_sku", null: false
    t.integer "quantity", null: false
    t.decimal "total_price", precision: 12, scale: 2, null: false
    t.decimal "unit_price", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["order_id", "product_id"], name: "index_order_items_on_order_id_and_product_id", unique: true
    t.index ["product_id"], name: "index_order_items_on_product_id"
    t.check_constraint "quantity > 0", name: "order_items_quantity_positive_check"
    t.check_constraint "total_price = (unit_price * quantity::numeric)", name: "order_items_total_matches_unit_price_check"
    t.check_constraint "total_price >= 0::numeric", name: "order_items_total_price_non_negative_check"
    t.check_constraint "unit_price >= 0::numeric", name: "order_items_unit_price_non_negative_check"
  end

  create_table "orders", force: :cascade do |t|
    t.jsonb "billing_address"
    t.string "cancellation_reason"
    t.datetime "cancelled_at"
    t.bigint "coupon_id"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "USD", null: false
    t.decimal "discount_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.citext "idempotency_key", null: false
    t.citext "number", null: false
    t.datetime "placed_at"
    t.jsonb "shipping_address", null: false
    t.decimal "shipping_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.string "status", default: "pending", null: false
    t.decimal "subtotal_amount", precision: 12, scale: 2, null: false
    t.decimal "tax_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_amount", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["coupon_id"], name: "index_orders_on_coupon_id"
    t.index ["idempotency_key"], name: "index_orders_on_idempotency_key", unique: true
    t.index ["number"], name: "index_orders_on_number", unique: true
    t.index ["status", "created_at"], name: "index_orders_on_status_and_created_at"
    t.index ["user_id", "created_at"], name: "index_orders_on_user_id_and_created_at", order: { created_at: :desc }
    t.check_constraint "(status::text = 'cancelled'::text) = (cancelled_at IS NOT NULL)", name: "orders_cancelled_at_matches_status_check"
    t.check_constraint "currency::text ~ '^[A-Z]{3}$'::text", name: "orders_currency_check"
    t.check_constraint "discount_amount <= subtotal_amount", name: "orders_discount_within_subtotal_check"
    t.check_constraint "discount_amount >= 0::numeric", name: "orders_discount_amount_non_negative_check"
    t.check_constraint "shipping_amount >= 0::numeric", name: "orders_shipping_amount_non_negative_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'paid'::character varying, 'processing'::character varying, 'shipped'::character varying, 'delivered'::character varying, 'cancelled'::character varying, 'refunded'::character varying]::text[])", name: "orders_status_check"
    t.check_constraint "subtotal_amount >= 0::numeric", name: "orders_subtotal_amount_non_negative_check"
    t.check_constraint "tax_amount >= 0::numeric", name: "orders_tax_amount_non_negative_check"
    t.check_constraint "total_amount = (subtotal_amount - discount_amount + tax_amount + shipping_amount)", name: "orders_total_matches_components_check"
    t.check_constraint "total_amount >= 0::numeric", name: "orders_total_amount_non_negative_check"
  end

  create_table "payments", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "USD", null: false
    t.string "failure_reason"
    t.citext "idempotency_key", null: false
    t.bigint "order_id", null: false
    t.datetime "processed_at"
    t.string "provider", default: "mock", null: false
    t.citext "provider_reference"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_payments_on_idempotency_key", unique: true
    t.index ["order_id"], name: "index_payments_on_order_id"
    t.index ["provider_reference"], name: "index_payments_on_provider_reference", unique: true, where: "(provider_reference IS NOT NULL)"
    t.index ["status", "created_at"], name: "index_payments_on_status_and_created_at"
    t.check_constraint "(status::text = 'failed'::text) = (failure_reason IS NOT NULL)", name: "payments_failure_reason_matches_status_check"
    t.check_constraint "amount > 0::numeric", name: "payments_amount_positive_check"
    t.check_constraint "currency::text ~ '^[A-Z]{3}$'::text", name: "payments_currency_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'authorized'::character varying, 'captured'::character varying, 'failed'::character varying, 'refunded'::character varying]::text[])", name: "payments_status_check"
  end

  create_table "product_images", force: :cascade do |t|
    t.string "alt_text"
    t.datetime "created_at", null: false
    t.boolean "is_primary", default: false, null: false
    t.integer "position", default: 0, null: false
    t.bigint "product_id", null: false
    t.string "storage_key", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "position"], name: "index_product_images_on_product_id_and_position"
    t.index ["product_id"], name: "index_product_images_on_one_primary_per_product", unique: true, where: "is_primary"
    t.check_constraint "\"position\" >= 0", name: "product_images_position_non_negative_check"
  end

  create_table "products", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.decimal "compare_at_price", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.decimal "price", precision: 12, scale: 2, null: false
    t.datetime "published_at"
    t.citext "sku", null: false
    t.citext "slug", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.integer "weight_grams"
    t.index ["category_id", "status"], name: "index_products_on_category_id_and_status"
    t.index ["sku"], name: "index_products_on_sku", unique: true
    t.index ["slug"], name: "index_products_on_slug", unique: true
    t.index ["status", "published_at"], name: "index_products_on_active_published_at", order: { published_at: :desc }, where: "((status)::text = 'active'::text)"
    t.check_constraint "compare_at_price IS NULL OR compare_at_price >= 0::numeric", name: "products_compare_at_price_non_negative_check"
    t.check_constraint "price >= 0::numeric", name: "products_price_non_negative_check"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'active'::character varying, 'archived'::character varying]::text[])", name: "products_status_check"
    t.check_constraint "weight_grams IS NULL OR weight_grams >= 0", name: "products_weight_non_negative_check"
  end

  create_table "reviews", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.bigint "order_item_id"
    t.bigint "product_id", null: false
    t.integer "rating", null: false
    t.string "status", default: "pending", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["order_item_id"], name: "index_reviews_on_order_item_id"
    t.index ["product_id", "created_at"], name: "index_reviews_on_approved_product_recency", order: { created_at: :desc }, where: "((status)::text = 'approved'::text)"
    t.index ["product_id"], name: "index_reviews_on_product_id"
    t.index ["user_id", "product_id"], name: "index_reviews_on_user_id_and_product_id", unique: true
    t.check_constraint "rating >= 1 AND rating <= 5", name: "reviews_rating_range_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying]::text[])", name: "reviews_status_check"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.string "first_name"
    t.datetime "last_login_at"
    t.string "last_name"
    t.string "password_digest", null: false
    t.string "role", default: "customer", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.check_constraint "email ~~ '%@%'::citext", name: "users_email_format_check"
    t.check_constraint "role::text = ANY (ARRAY['customer'::character varying, 'admin'::character varying]::text[])", name: "users_role_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'suspended'::character varying]::text[])", name: "users_status_check"
  end

  create_table "wishlist_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "wishlist_id", null: false
    t.index ["product_id"], name: "index_wishlist_items_on_product_id"
    t.index ["wishlist_id", "product_id"], name: "index_wishlist_items_on_wishlist_id_and_product_id", unique: true
  end

  create_table "wishlists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_wishlists_on_user_id", unique: true
  end

  add_foreign_key "addresses", "users", on_delete: :cascade
  add_foreign_key "cart_items", "carts", on_delete: :cascade
  add_foreign_key "cart_items", "products", on_delete: :cascade
  add_foreign_key "carts", "users", on_delete: :cascade
  add_foreign_key "categories", "categories", column: "parent_id", on_delete: :nullify
  add_foreign_key "inventories", "products", on_delete: :cascade
  add_foreign_key "order_items", "orders", on_delete: :cascade
  add_foreign_key "order_items", "products", on_delete: :restrict
  add_foreign_key "orders", "coupons", on_delete: :restrict
  add_foreign_key "orders", "users", on_delete: :restrict
  add_foreign_key "payments", "orders", on_delete: :cascade
  add_foreign_key "product_images", "products", on_delete: :cascade
  add_foreign_key "products", "categories", on_delete: :restrict
  add_foreign_key "reviews", "order_items", on_delete: :nullify
  add_foreign_key "reviews", "products", on_delete: :cascade
  add_foreign_key "reviews", "users", on_delete: :cascade
  add_foreign_key "wishlist_items", "products", on_delete: :cascade
  add_foreign_key "wishlist_items", "wishlists", on_delete: :cascade
  add_foreign_key "wishlists", "users", on_delete: :cascade
end
