# Base policy. Every action denies by default.
#
# A policy that forgets to define an action therefore fails CLOSED. The
# alternative — permissive defaults — means a missing method silently
# authorizes, which is invisible in code review and in tests that only assert
# the happy path.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index? = false
  def show? = false
  def create? = false
  def new? = create?
  def update? = false
  def edit? = update?
  def destroy? = false

  protected

  def admin?
    user&.admin?
  end

  # True when the record belongs to the acting user.
  #
  # Compares user_id rather than the association so it never triggers a query,
  # and requires both sides to be present so a nil user can never match a record
  # with a nil owner.
  def owner?
    return false if user.nil? || !record.respond_to?(:user_id)

    record.user_id.present? && record.user_id == user.id
  end

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    # Deliberately not implemented.
    #
    # Returning `scope` here would mean any collection whose policy forgets a
    # Scope silently exposes every row. Raising forces each resource to state
    # what its owner may see.
    def resolve
      raise NoMethodError, "#{self.class} must implement #resolve"
    end

    protected

    def admin?
      user&.admin?
    end
  end
end
