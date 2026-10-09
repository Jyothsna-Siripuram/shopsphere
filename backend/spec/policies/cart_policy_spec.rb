require "rails_helper"

RSpec.describe CartPolicy do
  subject(:policy) { described_class }

  let(:owner) { create(:user) }
  let(:stranger) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:cart) { create(:cart, user: owner) }

  permissions :show?, :update?, :checkout? do
    it "belongs to the owner alone" do
      expect(policy).to permit(owner, cart)
      expect(policy).not_to permit(stranger, cart)
      expect(policy).not_to permit(nil, cart)
    end

    # Staff have no business reading or editing a customer's basket. Not
    # building the capability is the strongest guarantee it is not misused.
    it "is denied even to administrators" do
      expect(policy).not_to permit(admin, cart)
    end
  end

  permissions :index?, :destroy? do
    it "is denied to everyone, including administrators" do
      expect(policy).not_to permit(owner, cart)
      expect(policy).not_to permit(admin, cart)
    end
  end

  describe "Scope" do
    it "resolves to the caller's own carts" do
      own = create(:cart, user: owner)
      create(:cart, user: stranger)

      expect(described_class::Scope.new(owner, Cart.all).resolve).to contain_exactly(own)
    end

    it "resolves to nothing for an unauthenticated caller" do
      cart

      expect(described_class::Scope.new(nil, Cart.all).resolve).to be_empty
    end

    # An administrator is not special here, unlike most other scopes.
    it "resolves to nothing for an administrator" do
      cart

      expect(described_class::Scope.new(admin, Cart.all).resolve).to be_empty
    end
  end
end
