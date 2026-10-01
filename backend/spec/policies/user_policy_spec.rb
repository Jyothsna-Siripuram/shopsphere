require "rails_helper"

RSpec.describe UserPolicy do
  subject(:policy) { described_class }

  let(:customer) { create(:user) }
  let(:other_customer) { create(:user) }
  let(:admin) { create(:user, :admin) }

  permissions :index? do
    it "is restricted to administrators" do
      expect(policy).to permit(admin, User)
      expect(policy).not_to permit(customer, User)
    end
  end

  permissions :show?, :update? do
    it "grants a customer access to their own record only" do
      expect(policy).to permit(customer, customer)
      expect(policy).not_to permit(customer, other_customer)
    end

    it "grants an administrator access to any record" do
      expect(policy).to permit(admin, other_customer)
    end
  end

  permissions :destroy? do
    # Orders reference users with ON DELETE RESTRICT; accounts are suspended,
    # never deleted.
    it "is denied to everyone" do
      expect(policy).not_to permit(admin, customer)
      expect(policy).not_to permit(customer, customer)
    end
  end

  permissions :change_role?, :suspend? do
    it "lets an administrator act on another account" do
      expect(policy).to permit(admin, customer)
    end

    # Without this, the last remaining administrator could demote or suspend
    # themselves and lock everyone out of the admin surface permanently.
    it "stops an administrator acting on their own account" do
      expect(policy).not_to permit(admin, admin)
    end

    it "denies a customer outright" do
      expect(policy).not_to permit(customer, other_customer)
    end
  end

  describe "#permitted_attributes" do
    it "withholds role and status from a customer editing themselves" do
      attributes = described_class.new(customer, customer).permitted_attributes

      expect(attributes).to contain_exactly(:first_name, :last_name, :email)
    end

    it "allows an administrator to set role and status" do
      attributes = described_class.new(admin, customer).permitted_attributes

      expect(attributes).to include(:role, :status)
    end
  end

  describe "Scope" do
    it "resolves to just themselves for a customer, so the index cannot enumerate users" do
      customer
      other_customer

      expect(described_class::Scope.new(customer, User.all).resolve).to contain_exactly(customer)
    end

    it "resolves to everyone for an administrator" do
      customer
      admin

      expect(described_class::Scope.new(admin, User.all).resolve.count).to eq(User.count)
    end
  end
end
