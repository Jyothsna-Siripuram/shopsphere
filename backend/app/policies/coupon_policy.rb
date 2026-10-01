class CouponPolicy < ApplicationPolicy
  # Coupon management is staff-only. Customers never browse coupons: listing
  # them would turn every unadvertised promotion into a public discount.
  def index? = admin?
  def show? = admin?
  def create? = admin?
  def update? = admin?
  def destroy? = admin?

  # Redemption is the customer-facing action, and it names a code rather than
  # exposing the record. Validity is decided by ApplyCoupon at checkout, where
  # the cart is known.
  def redeem? = user.present?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if admin?

      scope.none
    end
  end
end
