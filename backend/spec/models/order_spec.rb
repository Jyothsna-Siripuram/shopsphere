require "rails_helper"

RSpec.describe Order, type: :model do
  describe "total arithmetic" do
    # Mirrors the CHECK constraint, so a pricing bug is reported as a
    # validation error instead of surfacing as a StatementInvalid.
    it "rejects a total that disagrees with its components" do
      order = build(:order, subtotal_amount: 100, discount_amount: 10,
                            tax_amount: 5, shipping_amount: 0, total_amount: 100)

      expect(order).not_to be_valid
      expect(order.errors[:total_amount]).to be_present
    end

    it "accepts a total equal to subtotal minus discount plus tax and shipping" do
      order = build(:order, subtotal_amount: 100, discount_amount: 10,
                            tax_amount: 5, shipping_amount: 7.5, total_amount: 102.5)

      expect(order).to be_valid
    end
  end

  describe "#cancellable?" do
    it "allows cancellation before dispatch" do
      expect(build(:order, status: "pending")).to be_cancellable
      expect(build(:order, :paid)).to be_cancellable
    end

    # Once goods are in transit, cancellation becomes a return: different
    # workflow, different accounting.
    it "refuses cancellation once shipped or beyond" do
      expect(build(:order, :shipped)).not_to be_cancellable
      expect(build(:order, status: "delivered")).not_to be_cancellable
      expect(build(:order, :cancelled)).not_to be_cancellable
    end
  end

  describe "#current_payment" do
    # Payments are append-only: a retry creates a new row rather than mutating
    # the failed one, so the audit trail survives.
    it "returns the most recent payment attempt" do
      order = create(:order)
      create(:payment, :failed, order:, created_at: 2.hours.ago)
      latest = create(:payment, :captured, order:, created_at: 1.minute.ago)

      expect(order.reload.current_payment).to eq(latest)
    end
  end

  it "enforces a unique idempotency key so a retried checkout cannot duplicate" do
    create(:order, idempotency_key: "same-key")

    expect(build(:order, idempotency_key: "same-key")).not_to be_valid
  end

  describe ".with_detail_associations" do
    it "loads line items, products and payments without an N+1" do
      order = create(:order)
      create(:order_item, order:)
      create(:payment, order:)

      loaded = described_class.with_detail_associations.to_a

      # If eager loading were missing, touching these would emit further
      # queries; asserting the association is loaded is the direct check.
      expect(loaded.first.association(:order_items)).to be_loaded
      expect(loaded.first.order_items.first.association(:product)).to be_loaded
      expect(loaded.first.association(:payments)).to be_loaded
    end
  end
end
