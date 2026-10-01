require "rails_helper"

RSpec.describe ProductPolicy do
  subject(:policy) { described_class }

  let(:customer) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:published) { create(:product, status: "active", published_at: 1.day.ago) }
  let(:draft) { create(:product, :draft) }

  permissions :index? do
    it "is public, because browsing must not require an account" do
      expect(policy).to permit(nil, Product)
    end
  end

  permissions :show? do
    it "allows anyone to view a published product" do
      expect(policy).to permit(nil, published)
      expect(policy).to permit(customer, published)
    end

    # Otherwise an unreleased product could be found by guessing its slug.
    it "hides a draft from the public and from customers" do
      expect(policy).not_to permit(nil, draft)
      expect(policy).not_to permit(customer, draft)
    end

    it "shows a draft to an administrator" do
      expect(policy).to permit(admin, draft)
    end
  end

  permissions :create?, :update?, :manage_inventory? do
    it "is restricted to administrators" do
      expect(policy).to permit(admin, published)
      expect(policy).not_to permit(customer, published)
      expect(policy).not_to permit(nil, published)
    end
  end

  permissions :destroy? do
    # order_items reference products with ON DELETE RESTRICT; products are
    # archived so purchase history stays resolvable.
    it "is denied even to administrators" do
      expect(policy).not_to permit(admin, published)
    end
  end

  describe "Scope" do
    it "shows the public only published products" do
      published
      draft
      create(:product, :archived)

      expect(described_class::Scope.new(nil, Product.all).resolve).to contain_exactly(published)
    end

    it "shows an administrator every product regardless of status" do
      published
      draft

      expect(described_class::Scope.new(admin, Product.all).resolve.count).to eq(2)
    end
  end
end
