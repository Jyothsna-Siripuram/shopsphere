require "rails_helper"

RSpec.describe CategoryPolicy do
  subject(:policy) { described_class }

  let(:customer) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:category) { create(:category) }

  permissions :index?, :show? do
    it "is public, because the catalogue must be browsable without an account" do
      expect(policy).to permit(nil, category)
      expect(policy).to permit(customer, category)
    end
  end

  permissions :create?, :update?, :destroy? do
    it "is restricted to administrators" do
      expect(policy).to permit(admin, category)
      expect(policy).not_to permit(customer, category)
      expect(policy).not_to permit(nil, category)
    end
  end

  describe "Scope" do
    it "resolves to every category for everyone" do
      category

      expect(described_class::Scope.new(nil, Category.all).resolve).to contain_exactly(category)
    end
  end

  # The policy permits destroy for an administrator, but products.category_id is
  # ON DELETE RESTRICT. The policy answers "may you", the constraint answers "is
  # it safe" — both are required, and this records that they are different
  # questions.
  it "permits deletion while the database still refuses a non-empty category" do
    create(:product, category: category)

    expect(described_class.new(admin, category).destroy?).to be(true)
    expect { category.destroy! }.to raise_error(ActiveRecord::InvalidForeignKey)
  end
end
