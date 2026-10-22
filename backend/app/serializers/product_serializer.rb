class ProductSerializer
  # Two shapes rather than one.
  #
  # A listing of 24 products does not need every description and every image,
  # and sending them makes the payload grow with fields nobody renders. The
  # detail shape is opt-in so the listing stays small.
  def self.call(product, detail: false)
    payload = {
      id: product.id,
      name: product.name,
      slug: product.slug,
      sku: product.sku,
      # Money as a STRING, never a JSON number (ADR-002).
      #
      # JavaScript's number is an IEEE-754 double, so a client summing JSON
      # numbers drifts from the server by cents — 0.1 + 0.2 is
      # 0.30000000000000004. The string survives the round trip intact and the
      # client parses it with a decimal library.
      price: MoneyFormat.call(product.price),
      compare_at_price: MoneyFormat.call(product.compare_at_price),
      currency: "USD",
      status: product.status,
      category: category_payload(product),
      # `in_stock` rather than the raw quantity: exact stock is commercially
      # sensitive and lets a competitor measure sales velocity by polling.
      # "Can I buy it" is all a storefront needs.
      in_stock: product.inventory.present? && product.inventory.in_stock?,
      primary_image: image_payload(product.primary_image),
      published_at: product.published_at&.iso8601
    }

    return payload unless detail

    payload.merge(
      description: product.description,
      weight_grams: product.weight_grams,
      images: product.product_images.map { |image| image_payload(image) },
      created_at: product.created_at.iso8601
    )
  end

  # Administrators see the operational figures a storefront must not expose.
  def self.admin(product)
    call(product, detail: true).merge(
      available_quantity: product.inventory&.available_quantity,
      reorder_threshold: product.inventory&.reorder_threshold,
      low_stock: product.inventory&.low_stock?
    )
  end

  def self.category_payload(product)
    return nil if product.category.nil?

    { id: product.category.id, name: product.category.name, slug: product.category.slug }
  end

  def self.image_payload(image)
    return nil if image.nil?

    {
      id: image.id,
      storage_key: image.storage_key,
      alt_text: image.alt_text,
      position: image.position,
      is_primary: image.is_primary
    }
  end

  private_class_method :category_payload, :image_payload
end
