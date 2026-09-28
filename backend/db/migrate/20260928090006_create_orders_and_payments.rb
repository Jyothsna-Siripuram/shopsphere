class CreateOrdersAndPayments < ActiveRecord::Migration[8.1]
  ORDER_STATUSES = %w[pending paid processing shipped delivered cancelled refunded].freeze
  PAYMENT_STATUSES = %w[pending authorized captured failed refunded].freeze

  def change
    create_table :orders do |t|
      # Restrict, not cascade: deleting a customer must never delete financial
      # history. Account removal becomes an anonymisation problem, which is the
      # correct place to solve it.
      # index: false because the (user_id, created_at) index below covers
      # lookups by user_id from its leading column.
      t.references :user, null: false, index: false, foreign_key: { on_delete: :restrict }
      t.citext :number, null: false
      t.string :status, null: false, default: "pending"

      # Totals are stored, not recomputed on read. A recomputed total would
      # change retroactively when a product price or tax rate changes, which
      # makes historical orders and invoices wrong.
      t.decimal :subtotal_amount, precision: 12, scale: 2, null: false
      t.decimal :discount_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :tax_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :shipping_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :total_amount, precision: 12, scale: 2, null: false
      t.string :currency, null: false, limit: 3, default: "USD"

      t.references :coupon, foreign_key: { on_delete: :restrict }

      # Snapshots, not foreign keys. Addresses are editable; an order is a
      # permanent record of where goods were actually sent. Linking would let a
      # 2027 profile edit silently rewrite a 2026 invoice.
      t.jsonb :shipping_address, null: false
      t.jsonb :billing_address

      # Deduplicates checkout. A client retrying after a timeout sends the same
      # key; the unique index below turns the second attempt into a conflict the
      # service can resolve by returning the original order rather than charging
      # twice. Row locking prevents overselling; this prevents double-ordering.
      # They are separate problems with separate mechanisms.
      t.citext :idempotency_key, null: false

      t.datetime :placed_at
      t.datetime :cancelled_at
      t.string :cancellation_reason

      t.timestamps

      t.index :number, unique: true
      t.index :idempotency_key, unique: true

      t.check_constraint "status IN (#{quoted(ORDER_STATUSES)})", name: "orders_status_check"
      t.check_constraint "currency ~ '^[A-Z]{3}$'", name: "orders_currency_check"

      %w[subtotal_amount discount_amount tax_amount shipping_amount total_amount].each do |column|
        t.check_constraint "#{column} >= 0", name: "orders_#{column}_non_negative_check"
      end

      # The arithmetic invariant. If a pricing bug ever produces a total that
      # does not equal its own components, the write fails instead of quietly
      # charging the wrong amount. This is the single most valuable constraint
      # on the table: money that does not add up is the one error customers
      # always notice.
      t.check_constraint(
        "total_amount = subtotal_amount - discount_amount + tax_amount + shipping_amount",
        name: "orders_total_matches_components_check"
      )

      # A discount cannot exceed what is being discounted.
      t.check_constraint "discount_amount <= subtotal_amount",
                         name: "orders_discount_within_subtotal_check"

      # Cancellation metadata must be consistent: either cancelled with a
      # timestamp, or not cancelled at all.
      t.check_constraint(
        "(status = 'cancelled') = (cancelled_at IS NOT NULL)",
        name: "orders_cancelled_at_matches_status_check"
      )

      # "My orders", newest first — the single most frequent authenticated read
      # in the application. Composite so the user filter and the reverse
      # chronological sort are served by one index scan with no sort step.
      t.index %i[user_id created_at], order: { created_at: :desc }

      # Admin order queue filters by status and works oldest-first.
      t.index %i[status created_at]
    end

    create_table :order_items do |t|
      # index: false because the unique (order_id, product_id) index below
      # already serves lookups by order_id from its leading column. A redundant
      # single-column index costs a write on every insert and buys nothing.
      t.references :order, null: false, index: false, foreign_key: { on_delete: :cascade }
      # Restrict: an order line must always resolve to the product that was
      # sold, for returns, accounting and reporting. Keeps its own index, which
      # sales reporting uses to aggregate by product across orders.
      t.references :product, null: false, foreign_key: { on_delete: :restrict }

      # Snapshots taken at purchase time. Joining to products for these would
      # make historical orders mutate whenever the catalogue is edited: a
      # renamed or repriced product would rewrite every past invoice.
      t.string :product_name, null: false
      t.citext :product_sku, null: false
      t.decimal :unit_price, precision: 12, scale: 2, null: false

      t.integer :quantity, null: false
      t.decimal :total_price, precision: 12, scale: 2, null: false

      t.timestamps

      t.check_constraint "quantity > 0", name: "order_items_quantity_positive_check"
      t.check_constraint "unit_price >= 0", name: "order_items_unit_price_non_negative_check"
      t.check_constraint "total_price >= 0", name: "order_items_total_price_non_negative_check"

      # Line arithmetic must hold, for the same reason the order total must.
      t.check_constraint "total_price = unit_price * quantity",
                         name: "order_items_total_matches_unit_price_check"

      # One line per product per order, consistent with cart_items. Also serves
      # "all lines for this order" from its leading column, which is why
      # order_id carries no separate index of its own.
      t.index %i[order_id product_id], unique: true
    end

    create_table :payments do |t|
      t.references :order, null: false, foreign_key: { on_delete: :cascade }
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency, null: false, limit: 3, default: "USD"
      t.string :status, null: false, default: "pending"
      t.string :provider, null: false, default: "mock"
      # Provider-side identifier. Unique so a provider callback delivered twice
      # cannot be recorded as two distinct payments.
      t.citext :provider_reference
      t.citext :idempotency_key, null: false
      t.string :failure_reason
      t.datetime :processed_at

      t.timestamps

      t.check_constraint "status IN (#{quoted(PAYMENT_STATUSES)})", name: "payments_status_check"
      t.check_constraint "amount > 0", name: "payments_amount_positive_check"
      t.check_constraint "currency ~ '^[A-Z]{3}$'", name: "payments_currency_check"

      # A failure must explain itself; a success must not claim a failure
      # reason. Keeps the audit trail trustworthy.
      t.check_constraint(
        "(status = 'failed') = (failure_reason IS NOT NULL)",
        name: "payments_failure_reason_matches_status_check"
      )

      t.index :idempotency_key, unique: true
      # Partial: most payments never receive a provider reference immediately,
      # and NULLs do not conflict in a unique index anyway. Indexing only the
      # populated rows keeps it small.
      t.index :provider_reference, unique: true, where: "provider_reference IS NOT NULL",
              name: "index_payments_on_provider_reference"
      t.index %i[status created_at]
    end
  end

  private

  def quoted(values)
    values.map { |value| "'#{value}'" }.join(", ")
  end
end
