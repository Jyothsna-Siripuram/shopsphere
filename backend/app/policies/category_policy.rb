class CategoryPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def create? = admin?
  def update? = admin?

  # Deletion is permitted, but products.category_id is ON DELETE RESTRICT, so
  # the database refuses while the category still holds products. The policy
  # answers "may you", the constraint answers "is it safe" — both are needed.
  def destroy? = admin?

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
