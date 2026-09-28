require "rails_helper"

RSpec.describe Inventory, type: :model do
  describe "#in_stock?" do
    it "compares against the requested quantity, not merely zero" do
      inventory = build(:inventory, available_quantity: 3)

      expect(inventory.in_stock?).to be(true)
      expect(inventory.in_stock?(3)).to be(true)
      expect(inventory.in_stock?(4)).to be(false)
    end
  end

  describe "#low_stock?" do
    it "is true at or below the reorder threshold" do
      expect(build(:inventory, available_quantity: 2, reorder_threshold: 2)).to be_low_stock
      expect(build(:inventory, available_quantity: 1, reorder_threshold: 2)).to be_low_stock
      expect(build(:inventory, available_quantity: 3, reorder_threshold: 2)).not_to be_low_stock
    end
  end

  describe ".low_stock" do
    it "finds rows needing replenishment by comparing two columns in SQL" do
      needs_restock = create(:inventory, available_quantity: 1, reorder_threshold: 5)
      create(:inventory, available_quantity: 50, reorder_threshold: 5)

      expect(described_class.low_stock).to contain_exactly(needs_restock)
    end
  end

  it "mirrors the non-negative constraint as a readable validation error" do
    inventory = build(:inventory, available_quantity: -1)

    expect(inventory).not_to be_valid
    expect(inventory.errors[:available_quantity]).to be_present
  end

  # The model deliberately exposes no decrement method: doing so safely needs a
  # row lock taken across a whole basket inside the checkout transaction.
  # See ADR-001 and Inventory::Reserve, arriving on Day 11.
  it "does not expose an unguarded decrement" do
    expect(described_class.instance_methods).not_to include(:decrement_stock!)
  end
end
