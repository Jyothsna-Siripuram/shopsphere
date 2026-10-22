# Shared by the cart and cart-item controllers.
module CartLoading
  extend ActiveSupport::Concern

  included do
    rescue_from Carts::InvalidLine, with: :render_invalid_line
  end

  private

  # Through policy_scope, so the cart can only ever be the caller's own.
  def current_cart
    policy_scope(Cart).active.with_pricing_associations.first
  end

  # Every mutation answers with the whole cart, not the line it touched: the
  # client has to redraw the subtotal, item count and checkout state anyway,
  # and returning them saves the follow-up GET.
  def render_cart(cart, status: :ok)
    cart = Cart.with_pricing_associations.find(cart.id) if cart.persisted?

    render json: { data: CartSerializer.call(cart) }, status: status
  end

  def render_invalid_line(error)
    render_error(code: error.code, message: error.message,
                 status: :unprocessable_content, details: error.details)
  end
end
