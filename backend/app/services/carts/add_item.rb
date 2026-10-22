module Carts
  # Adds a product to the user's active cart, or increases the quantity of the
  # line already holding it.
  #
  # The increment is ONE statement:
  #
  #   INSERT ... ON CONFLICT (cart_id, product_id)
  #   DO UPDATE SET quantity = LEAST(cart_items.quantity + EXCLUDED.quantity, 99)
  #
  # The obvious version — find the line, add in Ruby, save — is a
  # read-modify-write race. Two concurrent "add one" requests both read 1 and
  # both write 2, losing an item. Doing the arithmetic in the UPDATE makes
  # PostgreSQL serialise the two writes on the row lock, so the second sees the
  # first's result. No explicit lock and no transaction is needed for that.
  #
  # Stock is checked here only as "can this be bought at all". Whether the
  # requested QUANTITY is in stock is reported per line (CartItem#availability)
  # rather than refused: a cart is not a reservation, and rejecting "add 5"
  # with "only 3 left" would disclose the stock level. Checkout enforces
  # quantity under lock (ADR-001).
  class AddItem
    def self.call(...) = new(...).call

    def initialize(user:, product:, quantity:)
      @user = user
      @product = product
      @quantity = quantity
    end

    def call
      validate!

      cart = Cart.find_or_create_active_for!(user)
      now = Time.current

      CartItem.upsert(
        { cart_id: cart.id, product_id: product.id, quantity: parsed_quantity,
          created_at: now, updated_at: now },
        unique_by: %i[cart_id product_id],
        # The cap is applied in SQL too: upsert bypasses model validations,
        # and without LEAST two adds of 60 would store 120.
        on_duplicate: Arel.sql(<<~SQL.squish)
          quantity = LEAST(cart_items.quantity + EXCLUDED.quantity, #{CartItem::MAX_QUANTITY}),
          updated_at = EXCLUDED.updated_at
        SQL
      )

      # Recorded on the cart so a later abandoned-cart sweep (Day 16) can tell
      # an idle cart from one being edited, without reading every line.
      cart.touch(time: now)
      cart
    end

    private

    attr_reader :user, :product, :quantity

    def validate!
      unless parsed_quantity&.between?(1, CartItem::MAX_QUANTITY)
        raise InvalidLine.new(
          "Quantity must be a whole number from 1 to #{CartItem::MAX_QUANTITY}",
          code: "validation_failed",
          details: { quantity: [ "must be a whole number from 1 to #{CartItem::MAX_QUANTITY}" ] }
        )
      end

      return if product.inventory&.in_stock?

      raise InvalidLine.new("This product is currently unavailable", code: "out_of_stock")
    end

    # Integer(), not to_i: "2abc".to_i is 2 and "abc".to_i is 0, so to_i would
    # quietly accept garbage. Integer("2abc") raises; exception: false turns
    # that into nil, which validate! rejects.
    def parsed_quantity
      return @parsed_quantity if defined?(@parsed_quantity)

      @parsed_quantity = quantity.is_a?(Integer) ? quantity : Integer(quantity.to_s, 10, exception: false)
    end
  end
end
