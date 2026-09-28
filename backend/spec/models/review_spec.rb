require "rails_helper"

RSpec.describe Review, type: :model do
  it "allows one review per customer per product" do
    user = create(:user)
    product = create(:product)
    create(:review, user:, product:)

    expect(build(:review, user:, product:)).not_to be_valid
  end

  it "rejects a rating outside one to five" do
    expect(build(:review, rating: 0)).not_to be_valid
    expect(build(:review, rating: 6)).not_to be_valid
    expect(build(:review, rating: 3)).to be_valid
  end

  describe "verified purchase" do
    # Without this check a customer could cite someone else's purchase to earn
    # a verified badge. It spans three tables, which is why it lives in the
    # model rather than in a CHECK constraint.
    it "refuses an order item belonging to a different customer" do
      reviewer = create(:user)
      other_order = create(:order, user: create(:user))
      order_item = create(:order_item, order: other_order)

      review = build(:review, user: reviewer, product: order_item.product, order_item:)

      expect(review).not_to be_valid
      expect(review.errors[:order_item]).to be_present
    end

    it "accepts an order item from the reviewer's own order" do
      reviewer = create(:user)
      order_item = create(:order_item, order: create(:order, user: reviewer))

      review = build(:review, user: reviewer, product: order_item.product, order_item:)

      expect(review).to be_valid
      expect(review).to be_verified_purchase
    end
  end

  describe ".visible" do
    it "excludes anything not approved, so moderation actually gates publication" do
      approved = create(:review, status: "approved")
      create(:review, :pending, user: create(:user))
      create(:review, status: "rejected", user: create(:user))

      expect(described_class.visible).to contain_exactly(approved)
    end
  end
end
