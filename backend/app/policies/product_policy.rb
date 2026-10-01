class ProductPolicy < ApplicationPolicy
  # The catalogue is public: browsing must not require an account.
  def index? = true

  # A draft or archived product is visible only to administrators, so an
  # unreleased product cannot be found by guessing its slug.
  def show?
    admin? || record.published?
  end

  def create? = admin?
  def update? = admin?

  # Archived, never destroyed: order_items reference products with
  # ON DELETE RESTRICT so history stays intact.
  def destroy? = false

  def manage_inventory? = admin?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if admin?

      scope.published
    end
  end
end
