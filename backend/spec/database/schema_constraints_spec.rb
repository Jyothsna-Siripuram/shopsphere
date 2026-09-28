require "rails_helper"

# These specs assert that the database rejects invalid data by itself.
#
# Every statement here goes through raw SQL rather than an Active Record model,
# because the guarantee under test is precisely the one that survives when
# validations are bypassed: update_all, a Sidekiq job, a bulk admin edit, or a
# console session at 2am.
RSpec.describe "Schema constraints", type: :schema do
  describe "inventories" do
    # The single most important constraint in the schema.
    #
    # Checkout prevents overselling by locking the inventory row and checking
    # availability before it decrements. That mechanism lives in application
    # code and a future code path can forget it. This constraint means
    # forgetting it produces a loud failure rather than a silent oversell.
    it "refuses to let stock fall below zero" do
      product_id = create_product
      create_inventory(product_id:, available_quantity: 1)

      expect_constraint_violation do
        execute("UPDATE inventories SET available_quantity = available_quantity - 2 WHERE product_id = #{product_id}")
      end
    end

    it "allows stock to reach exactly zero" do
      product_id = create_product
      create_inventory(product_id:, available_quantity: 1)

      execute("UPDATE inventories SET available_quantity = available_quantity - 1 WHERE product_id = #{product_id}")

      quantity = execute("SELECT available_quantity FROM inventories WHERE product_id = #{product_id}")
                 .first.fetch("available_quantity")
      expect(quantity).to eq(0)
    end

    it "permits only one inventory row per product" do
      product_id = create_product
      create_inventory(product_id:)

      expect_constraint_violation { create_inventory(product_id:) }
    end
  end

  describe "orders" do
    # Money that does not add up is the error customers always notice.
    it "rejects a total that does not equal its own components" do
      user_id = create_user

      expect_constraint_violation do
        create_order(user_id:, subtotal: "100.00", discount: "10.00", tax: "5.00",
                     shipping: "0.00", total: "100.00")
      end
    end

    it "accepts a total that equals subtotal minus discount plus tax and shipping" do
      user_id = create_user

      order_id = create_order(user_id:, subtotal: "100.00", discount: "10.00", tax: "5.00",
                              shipping: "7.50", total: "102.50")

      expect(order_id).to be_present
    end

    it "rejects a discount larger than the subtotal" do
      user_id = create_user

      expect_constraint_violation do
        create_order(user_id:, subtotal: "10.00", discount: "20.00", total: "-10.00")
      end
    end

    # Prevents an order that claims to be cancelled but has no cancellation
    # timestamp, and an order carrying a stale cancelled_at after being revived.
    it "requires cancelled_at to agree with a cancelled status" do
      user_id = create_user

      expect_constraint_violation do
        create_order(user_id:, status: "cancelled", cancelled_at: "NULL")
      end
    end

    it "enforces a unique idempotency key so a retried checkout cannot duplicate an order" do
      user_id = create_user
      create_order(user_id:, number: "SS-1", idempotency_key: "duplicate-key")

      expect_constraint_violation do
        create_order(user_id:, number: "SS-2", idempotency_key: "duplicate-key")
      end
    end
  end

  describe "order_items" do
    it "rejects a line whose total does not equal unit price times quantity" do
      user_id = create_user
      product_id = create_product
      order_id = create_order(user_id:)

      expect_constraint_violation do
        execute(<<~SQL.squish)
          INSERT INTO order_items (
            order_id, product_id, product_name, product_sku, unit_price,
            quantity, total_price, created_at, updated_at
          )
          VALUES (#{order_id}, #{product_id}, 'Runner', 'SKU-1', 10.00, 3, 25.00, now(), now())
        SQL
      end
    end
  end

  describe "carts" do
    # Two concurrent "add to cart" requests both finding no cart would otherwise
    # create two, splitting the customer's items between them.
    it "allows only one active cart per user" do
      user_id = create_user
      create_cart(user_id:)

      expect_constraint_violation { create_cart(user_id:) }
    end

    it "still allows historical converted carts alongside an active one" do
      user_id = create_user
      create_cart(user_id:, status: "converted")
      create_cart(user_id:, status: "converted")

      expect { create_cart(user_id:, status: "active") }.not_to raise_error
    end
  end

  describe "users" do
    # citext, not a LOWER() index. A query that forgets to downcase cannot
    # bypass this.
    it "treats email addresses as case-insensitive for uniqueness" do
      create_user(email: "Customer@Example.com")

      expect_constraint_violation { create_user(email: "customer@example.com") }
    end

    it "rejects a role outside the permitted set" do
      expect_constraint_violation { create_user(email: "root@example.com", role: "superadmin") }
    end
  end

  describe "reviews" do
    # The product rating average is computed with SQL aggregation, so a single
    # out-of-range row would skew a score with no validation ever running.
    it "rejects a rating outside one to five" do
      user_id = create_user
      product_id = create_product

      expect_constraint_violation do
        execute(<<~SQL.squish)
          INSERT INTO reviews (user_id, product_id, rating, status, created_at, updated_at)
          VALUES (#{user_id}, #{product_id}, 6, 'approved', now(), now())
        SQL
      end
    end

    it "allows only one review per customer per product" do
      user_id = create_user
      product_id = create_product
      insert = <<~SQL.squish
        INSERT INTO reviews (user_id, product_id, rating, status, created_at, updated_at)
        VALUES (#{user_id}, #{product_id}, 5, 'approved', now(), now())
      SQL
      execute(insert)

      expect_constraint_violation { execute(insert) }
    end
  end

  describe "coupons" do
    it "rejects a percentage discount above one hundred" do
      expect_constraint_violation do
        execute(<<~SQL.squish)
          INSERT INTO coupons (code, discount_type, discount_value, minimum_order_amount,
                               times_used, active, created_at, updated_at)
          VALUES ('TOOMUCH', 'percentage', 150.00, 0, 0, true, now(), now())
        SQL
      end
    end

    it "rejects a validity window that closes before it opens" do
      expect_constraint_violation do
        execute(<<~SQL.squish)
          INSERT INTO coupons (code, discount_type, discount_value, minimum_order_amount,
                               times_used, active, starts_at, expires_at, created_at, updated_at)
          VALUES ('BACKWARDS', 'fixed_amount', 5.00, 0, 0, true,
                  now(), now() - interval '1 day', now(), now())
        SQL
      end
    end
  end
end
