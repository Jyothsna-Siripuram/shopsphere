class CartSerializer
  # Expects a cart loaded through Cart.with_pricing_associations, or an
  # unsaved Cart for a customer who has not added anything yet. Both render the
  # same shape, so a client never special-cases "no cart".
  def self.call(cart)
    {
      id: cart.id,
      items: cart.cart_items.map { |item| item_payload(item) },
      item_count: cart.item_count,
      # Money as a two-place string (ADR-002). A subtotal of live prices only:
      # discounts, tax and shipping are decided at checkout and stored on the
      # order, never here.
      subtotal: MoneyFormat.call(cart.items_subtotal),
      currency: "USD",
      checkout_ready: cart.checkout_ready?,
      updated_at: cart.updated_at&.iso8601
    }
  end

  def self.item_payload(item)
    product = item.product

    {
      id: item.id,
      quantity: item.quantity,
      unit_price: MoneyFormat.call(item.unit_price),
      line_total: MoneyFormat.call(item.line_total),
      availability: item.availability,
      product: {
        id: product.id,
        name: product.name,
        slug: product.slug,
        primary_image: image_payload(product.primary_image)
      }
    }
  end

  def self.image_payload(image)
    return nil if image.nil?

    { storage_key: image.storage_key, alt_text: image.alt_text }
  end

  private_class_method :item_payload, :image_payload
end
