class WishlistPolicy < ApplicationPolicy
  def show? = owner?
  def update? = owner?

  # Private to the customer, and not an administrative concern.
  def index? = false
  def destroy? = false

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.nil?

      scope.where(user_id: user.id)
    end
  end
end
