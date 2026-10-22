module Api
  module V1
    class CartItemsController < ApplicationController
      include CartLoading

      before_action :set_cart_item, only: %i[update destroy]

      # POST adds and INCREMENTS: posting "1 shoe" twice leaves two shoes. That
      # is what an "add to cart" button means, and it is also why this request
      # is not idempotent — a client retrying a timed-out POST can double-add.
      # PATCH, which SETS the quantity, is the idempotent alternative.
      def create
        # Authorized before the cart can be created, so a refused request
        # leaves nothing behind.
        authorize Cart.new(user: current_user), :update?

        # Product.published, not the product policy scope: adding to a cart
        # is a customer action even when the caller is an administrator, and
        # a draft is 404 here exactly as it is on the product page.
        product = Product.published.includes(:inventory).find(params.expect(:product_id))

        cart = Carts::AddItem.call(user: current_user, product: product,
                                   quantity: params.fetch(:quantity, 1))

        render_cart(cart)
      end

      # Sets the quantity outright, so repeating the request is harmless. Zero
      # is refused rather than treated as removal: DELETE says that, and a
      # quantity of 0 arriving from a buggy stepper should not silently empty a
      # line.
      def update
        if @cart_item.update(quantity: params.expect(:quantity))
          @cart_item.cart.touch
          render_cart(@cart_item.cart)
        else
          render_error(code: "validation_failed", message: "The cart line could not be updated",
                       status: :unprocessable_content,
                       details: @cart_item.errors.to_hash(true))
        end
      end

      def destroy
        @cart_item.destroy!
        @cart_item.cart.touch

        render_cart(@cart_item.cart)
      end

      private

      # Looked up through the caller's own active cart. Another customer's
      # line id is therefore 404, not 403 — the same anti-enumeration rule as
      # addresses — and so is a line in one of the caller's converted carts.
      def set_cart_item
        cart = policy_scope(Cart).active.first
        raise ActiveRecord::RecordNotFound if cart.nil?

        authorize cart, :update?
        @cart_item = cart.cart_items.find(params[:id])
      end
    end
  end
end
