module Api
  module V1
    # The acting user's cart, as a singular resource: there is no cart id in
    # the path, so there is no way to address another customer's basket.
    class CartsController < ApplicationController
      include CartLoading

      # Never writes. A customer who has added nothing gets an empty unsaved
      # cart in the same shape as a real one: creating a row on GET would make
      # a read unsafe, and every logged-in page view that draws a cart badge
      # would insert a cart nobody uses.
      def show
        cart = current_cart || Cart.new(user: current_user)
        authorize cart

        render_cart(cart)
      end

      # Empties the cart, keeping the cart row itself. Idempotent: clearing an
      # already-empty cart (or a missing one) is still 204.
      def destroy
        cart = current_cart
        authorize cart || Cart.new(user: current_user), :update?

        if cart
          # The explicit strategy is not decoration. On a has_many with no
          # `dependent:` option — this project's convention, see the README —
          # a bare delete_all NULLIFIES the foreign key instead of deleting.
          # Only the NOT NULL constraint on cart_id turned that into an error
          # rather than a pile of orphaned lines.
          cart.cart_items.delete_all(:delete_all)
          cart.touch
        end

        head :no_content
      end
    end
  end
end
