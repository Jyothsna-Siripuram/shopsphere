require "rails_helper"

RSpec.describe WishlistPolicy do
  subject(:policy) { described_class }

  let(:owner) { create(:user) }
  let(:stranger) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:wishlist) { create(:wishlist, user: owner) }

  permissions :show?, :update? do
    it "belongs to the owner alone, administrators included" do
      expect(policy).to permit(owner, wishlist)
      expect(policy).not_to permit(stranger, wishlist)
      expect(policy).not_to permit(admin, wishlist)
      expect(policy).not_to permit(nil, wishlist)
    end
  end

  permissions :index?, :destroy? do
    it "is denied to everyone" do
      expect(policy).not_to permit(owner, wishlist)
      expect(policy).not_to permit(admin, wishlist)
    end
  end

  describe "Scope" do
    it "resolves to the caller's own wishlist only" do
      own = create(:wishlist, user: owner)
      create(:wishlist, user: stranger)

      expect(described_class::Scope.new(owner, Wishlist.all).resolve).to contain_exactly(own)
    end

    it "resolves to nothing without a user" do
      wishlist

      expect(described_class::Scope.new(nil, Wishlist.all).resolve).to be_empty
    end
  end
end
