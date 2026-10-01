class CartPolicy < ApplicationPolicy
  def show? = owner?
  def update? = owner?
  def checkout? = owner?

  # A cart is not administrable. Staff have no business reading or editing a
  # customer's basket, and not building the capability is the cleanest way to
  # guarantee it is not misused.
  def index? = false
  def destroy? = false

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.nil?

      scope.where(user_id: user.id)
    end
  end
end
