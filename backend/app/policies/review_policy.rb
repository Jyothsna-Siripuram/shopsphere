class ReviewPolicy < ApplicationPolicy
  # Reviews are public, but only approved ones — the Scope enforces that.
  def index? = true

  def show?
    admin? || record.approved? || owner?
  end

  def create? = user.present?

  # A customer edits their own review; an administrator does not rewrite
  # customer words, only moderates them.
  def update? = owner?

  def destroy? = owner? || admin?

  # Moderation is a staff action, and an author must never approve their own
  # review — that would make moderation decorative.
  def moderate?
    admin? && !owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if admin?
      return scope.visible if user.nil?

      # An author sees their own review while it is pending, so submitting does
      # not look like it silently failed.
      scope.where(status: "approved").or(scope.where(user_id: user.id))
    end
  end
end
