require "rails_helper"

RSpec.describe CouponPolicy do
  subject(:policy) { described_class }

  let(:customer) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:coupon) { create(:coupon) }

  permissions :index?, :show?, :create?, :update?, :destroy? do
    # Listing coupons would turn every unadvertised promotion into a public
    # discount, so the whole record surface is staff-only.
    it "is restricted to administrators" do
      expect(policy).to permit(admin, coupon)
      expect(policy).not_to permit(customer, coupon)
      expect(policy).not_to permit(nil, coupon)
    end
  end

  permissions :redeem? do
    # The customer-facing action names a code rather than exposing the record.
    it "is available to any signed-in customer" do
      expect(policy).to permit(customer, coupon)
      expect(policy).not_to permit(nil, coupon)
    end
  end

  describe "Scope" do
    it "resolves to everything for an administrator" do
      coupon

      expect(described_class::Scope.new(admin, Coupon.all)).to be_present
      expect(described_class::Scope.new(admin, Coupon.all).resolve).to contain_exactly(coupon)
    end

    # This is exactly the case the Day 7 index? fix mattered for: without an
    # authorize call, a customer would have received 200 with an empty array
    # instead of 403.
    it "resolves to nothing for a customer" do
      coupon

      expect(described_class::Scope.new(customer, Coupon.all).resolve).to be_empty
    end
  end
end
