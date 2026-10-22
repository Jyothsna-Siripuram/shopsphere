require "rails_helper"

RSpec.describe Cart do
  let(:user) { create(:user) }

  describe ".find_or_create_active_for!" do
    it "returns the existing active cart" do
      cart = create(:cart, user:)

      expect(described_class.find_or_create_active_for!(user)).to eq(cart)
    end

    it "creates an active cart when there is none" do
      cart = described_class.find_or_create_active_for!(user)

      expect(cart).to be_persisted.and be_active
    end

    it "ignores converted carts" do
      converted = create(:cart, user:, status: "converted")

      expect(described_class.find_or_create_active_for!(user)).not_to eq(converted)
    end
  end

  describe "#checkout_ready?" do
    it "is false for an empty cart" do
      expect(create(:cart)).not_to be_checkout_ready
    end

    it "is true only when every line is available" do
      cart = create(:cart)
      create(:cart_item, cart:, product: create(:product, :in_stock))
      expect(cart.reload).to be_checkout_ready

      create(:cart_item, cart:, product: create(:product, :out_of_stock))
      expect(cart.reload).not_to be_checkout_ready
    end
  end

  it "totals live prices and quantities" do
    cart = create(:cart)
    create(:cart_item, cart:, quantity: 2, product: create(:product, price: "10.25"))
    create(:cart_item, cart:, quantity: 1, product: create(:product, price: "4.50"))

    expect(cart.reload.items_subtotal).to eq(BigDecimal("25.00"))
    expect(cart.item_count).to eq(3)
  end
end

RSpec.describe CartItem do
  describe "#availability" do
    def line(product, quantity: 1)
      build(:cart_item, product:, quantity:)
    end

    it "is available when published and in stock for the quantity" do
      expect(line(create(:product, :in_stock, quantity: 3), quantity: 3).availability).to eq("available")
    end

    it "is insufficient_stock when some, but not enough, is in stock" do
      expect(line(create(:product, :in_stock, quantity: 3), quantity: 4).availability)
        .to eq("insufficient_stock")
    end

    it "is out_of_stock at zero or with no inventory row" do
      expect(line(create(:product, :out_of_stock)).availability).to eq("out_of_stock")
      expect(line(create(:product)).availability).to eq("out_of_stock")
    end

    # A product archived after it was added stays in the cart, flagged, rather
    # than vanishing without explanation.
    it "is unavailable once the product is archived or unpublished" do
      expect(line(create(:product, :archived)).availability).to eq("unavailable")
      expect(line(create(:product, :draft)).availability).to eq("unavailable")
    end
  end

  it "rejects a quantity above the maximum" do
    expect(build(:cart_item, quantity: CartItem::MAX_QUANTITY + 1)).not_to be_valid
  end
end
