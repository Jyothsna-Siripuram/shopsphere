require "rails_helper"

RSpec.describe OrderPolicy do
  subject(:policy) { described_class }

  let(:owner) { create(:user) }
  let(:stranger) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:order) { create(:order, user: owner) }

  permissions :show? do
    it "grants the owner and an administrator, and denies everyone else" do
      expect(policy).to permit(owner, order)
      expect(policy).to permit(admin, order)
      expect(policy).not_to permit(stranger, order)
      expect(policy).not_to permit(nil, order)
    end
  end

  permissions :update? do
    # An order is an immutable financial record; progress happens through
    # explicit transitions, never a general update.
    it "is denied to everyone including administrators" do
      expect(policy).not_to permit(owner, order)
      expect(policy).not_to permit(admin, order)
    end
  end

  permissions :cancel? do
    it "grants the owner before dispatch" do
      expect(policy).to permit(owner, create(:order, user: owner, status: "pending"))
      expect(policy).to permit(owner, create(:order, :paid, user: owner))
    end

    it "denies the owner once shipped, because that is a return not a cancellation" do
      expect(policy).not_to permit(owner, create(:order, :shipped, user: owner))
      expect(policy).not_to permit(owner, create(:order, status: "delivered", user: owner))
    end

    # Administrators get the same state restriction, not a bypass: reversing a
    # delivered order is a refund, which is a different operation.
    it "denies an administrator once shipped" do
      expect(policy).not_to permit(admin, create(:order, :shipped, user: owner))
    end

    it "denies a stranger even for a cancellable order" do
      expect(policy).not_to permit(stranger, order)
    end
  end

  permissions :mark_shipped?, :refund? do
    it "is restricted to administrators" do
      expect(policy).to permit(admin, order)
      expect(policy).not_to permit(owner, order)
    end
  end

  describe "Scope" do
    it "gives a customer only their own orders" do
      own = create(:order, user: owner)
      create(:order, user: stranger)

      expect(described_class::Scope.new(owner, Order.all).resolve).to contain_exactly(own)
    end

    it "gives an administrator every order" do
      create(:order, user: owner)
      create(:order, user: stranger)

      expect(described_class::Scope.new(admin, Order.all).resolve.count).to eq(2)
    end

    it "gives an unauthenticated caller nothing" do
      create(:order, user: owner)

      expect(described_class::Scope.new(nil, Order.all).resolve).to be_empty
    end
  end
end
