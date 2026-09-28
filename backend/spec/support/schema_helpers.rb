# Raw-SQL helpers for the schema constraint specs.
#
# These deliberately bypass Active Record models. The point of those specs is to
# prove the database rejects invalid data on its own, so going through a model
# would test the validation rather than the constraint.
module SchemaHelpers
  def execute(sql)
    ActiveRecord::Base.connection.execute(sql)
  end

  def insert_returning_id(sql)
    execute(sql).first.fetch("id")
  end

  # Asserts that a statement is rejected by the database.
  #
  # `requires_new: true` opens a SAVEPOINT. Without it the failed statement
  # would leave the surrounding test transaction in an aborted state, and every
  # later statement in the example would fail with "current transaction is
  # aborted" instead of reporting the real assertion.
  def expect_constraint_violation(&block)
    expect { ActiveRecord::Base.transaction(requires_new: true, &block) }
      .to raise_error(ActiveRecord::StatementInvalid)
  end

  def create_user(email: "customer@example.com", role: "customer")
    insert_returning_id(<<~SQL.squish)
      INSERT INTO users (email, password_digest, role, status, created_at, updated_at)
      VALUES ('#{email}', 'not-a-real-digest', '#{role}', 'active', now(), now())
      RETURNING id
    SQL
  end

  def create_category(slug: "footwear")
    insert_returning_id(<<~SQL.squish)
      INSERT INTO categories (name, slug, position, created_at, updated_at)
      VALUES ('Footwear', '#{slug}', 0, now(), now())
      RETURNING id
    SQL
  end

  def create_product(category_id: nil, slug: "runner", sku: "SKU-1", price: "49.99")
    category_id ||= create_category
    insert_returning_id(<<~SQL.squish)
      INSERT INTO products (name, slug, sku, category_id, price, status, created_at, updated_at)
      VALUES ('Runner', '#{slug}', '#{sku}', #{category_id}, #{price}, 'active', now(), now())
      RETURNING id
    SQL
  end

  def create_inventory(product_id:, available_quantity: 10)
    insert_returning_id(<<~SQL.squish)
      INSERT INTO inventories (product_id, available_quantity, reorder_threshold, created_at, updated_at)
      VALUES (#{product_id}, #{available_quantity}, 0, now(), now())
      RETURNING id
    SQL
  end

  def create_cart(user_id:, status: "active")
    insert_returning_id(<<~SQL.squish)
      INSERT INTO carts (user_id, status, created_at, updated_at)
      VALUES (#{user_id}, '#{status}', now(), now())
      RETURNING id
    SQL
  end

  # rubocop:disable Metrics/ParameterLists
  def create_order(user_id:, subtotal: "100.00", discount: "0.00", tax: "0.00",
                   shipping: "0.00", total: "100.00", status: "pending",
                   cancelled_at: "NULL", number: "SS-1", idempotency_key: "key-1")
    insert_returning_id(<<~SQL.squish)
      INSERT INTO orders (
        user_id, number, status, subtotal_amount, discount_amount, tax_amount,
        shipping_amount, total_amount, currency, shipping_address,
        idempotency_key, cancelled_at, created_at, updated_at
      )
      VALUES (
        #{user_id}, '#{number}', '#{status}', #{subtotal}, #{discount}, #{tax},
        #{shipping}, #{total}, 'USD', '{"line1":"1 Main St"}'::jsonb,
        '#{idempotency_key}', #{cancelled_at}, now(), now()
      )
      RETURNING id
    SQL
  end
  # rubocop:enable Metrics/ParameterLists
end

RSpec.configure do |config|
  config.include SchemaHelpers, type: :schema
end
