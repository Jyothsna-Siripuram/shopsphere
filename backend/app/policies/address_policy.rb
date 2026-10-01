class AddressPolicy < ApplicationPolicy
  # Any signed-in customer may list their own addresses; the Scope below is what
  # makes "their own" true.
  def index? = user.present?

  def show? = owner? || admin?
  def create? = user.present?
  def update? = owner?
  def destroy? = owner?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if admin?
      return scope.none if user.nil?

      scope.where(user_id: user.id)
    end
  end
end
