class OrderPolicy < ApplicationPolicy
  def index? = user.present?
  def show? = owner? || admin?
  def create? = user.present?

  # An order is an immutable financial record. Progress happens through explicit
  # transitions, never a general update, so there is no path that silently
  # rewrites a total or a shipping address after the fact.
  def update? = false

  def destroy? = false

  # A customer may cancel only their own order, and only before dispatch. Once
  # goods are in transit, cancellation becomes a return: a different workflow
  # with different accounting.
  #
  # An administrator may cancel from the same states — not from any state —
  # because reversing a delivered order is a refund, not a cancellation.
  def cancel?
    (owner? || admin?) && record.cancellable?
  end

  # Fulfilment transitions are staff actions.
  def mark_shipped? = admin?
  def mark_delivered? = admin?
  def refund? = admin?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if admin?
      return scope.none if user.nil?

      # Combined with the controller's policy_scope(...).find, this is what makes
      # another customer's order return 404 rather than 403: a 403 would confirm
      # the order exists and let an attacker enumerate order IDs.
      scope.where(user_id: user.id)
    end
  end
end
