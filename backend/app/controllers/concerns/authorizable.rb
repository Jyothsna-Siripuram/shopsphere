module Authorizable
  extend ActiveSupport::Concern

  included do
    include Pundit::Authorization

    # The most valuable lines in the authorization layer.
    #
    # An action that forgets to call `authorize` or `policy_scope` raises
    # instead of quietly serving data. Forgetting the check is the most common
    # authorization bug in Rails, and it is invisible: the endpoint works, the
    # happy-path test passes, and nothing indicates the rule was never applied.
    # These turn that silent vulnerability into a loud failure in development
    # and in CI.
    # Conditions rather than `only:`/`except:` action names.
    #
    # Rails 7.1 raises AbstractController::ActionNotFound when a callback names
    # an action the controller does not define, which is a good default — but a
    # concern mixed into EVERY controller cannot assume `index` exists. Using an
    # `if:` predicate keeps the guarantee without coupling the concern to any
    # particular action list.
    # A collection action must satisfy BOTH checks.
    #
    # policy_scope alone was not enough: it filters rows, but it never consults
    # Policy#index?. Every index? method in the codebase was therefore dead
    # code, and a resource whose index? is admin-only — CouponPolicy, for
    # instance — would have returned 200 with an empty array to a customer
    # instead of 403, because the Scope resolves to `none` for them.
    after_action :verify_authorized
    after_action :verify_policy_scoped, if: :collection_action?

    rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
    # A missing policy class must never mean "allowed". Pundit raises this when
    # no policy exists for a record, and it is treated as a server fault because
    # it is a programming error, not a client one.
    rescue_from Pundit::NotDefinedError, with: :render_policy_missing
  end

  private

  # Pundit calls this to find the acting user.
  def pundit_user
    current_user
  end

  # A collection action must be protected by a policy scope; a single-record
  # action must be protected by `authorize`. They are different guarantees, so
  # the verification differs.
  def collection_action?
    action_name == "index"
  end

  def render_forbidden(_error = nil)
    # 403 means "this exists and you cannot act on it".
    #
    # Records the user should not even know about return 404 instead, which
    # happens naturally because those controllers look records up through
    # `policy_scope(...).find`, raising RecordNotFound. A 403 there would
    # confirm the record exists and let an attacker enumerate other customers'
    # resource IDs.
    render_error(
      code: "forbidden",
      message: "You are not allowed to perform this action",
      status: :forbidden
    )
  end

  def render_policy_missing(error)
    Rails.logger.error(event: "pundit_policy_missing", message: error.message)

    render_error(
      code: "internal_error",
      message: "Something went wrong",
      status: :internal_server_error
    )
  end
end
