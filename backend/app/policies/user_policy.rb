class UserPolicy < ApplicationPolicy
  # Only administrators list customers.
  def index? = admin?

  # A customer may read their own record; an administrator may read any.
  def show? = admin? || self?

  def update? = admin? || self?

  # Accounts are suspended, never deleted: orders reference users with
  # ON DELETE RESTRICT, and destroying financial history is not a thing an API
  # should offer.
  def destroy? = false

  # Role changes are an administrative act, and an administrator must not be
  # able to demote themselves into locking the last admin out.
  def change_role?
    admin? && !self?
  end

  def suspend?
    admin? && !self?
  end

  # Attributes the acting user may submit. Returned as a list so the controller
  # cannot accidentally permit more than the policy intends — keeping the
  # allowlist next to the rules that justify it.
  def permitted_attributes
    base = %i[first_name last_name email]
    admin? ? base + %i[role status] : base
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if admin?
      return scope.none if user.nil?

      # A customer's "collection" of users is exactly themselves, so a leaked
      # index route cannot enumerate the customer base.
      scope.where(id: user.id)
    end
  end

  private

  def self?
    user.present? && record.is_a?(User) && record.id == user.id
  end
end
