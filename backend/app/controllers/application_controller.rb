class ApplicationController < ActionController::API
  include ActionController::Cookies
  include Authenticatable

  # Ordered most general first: Rails matches handlers bottom-up, so a later
  # declaration wins for a more specific class.
  rescue_from StandardError, with: :render_internal_error unless Rails.env.local?
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  # A unique index refusing a write is a conflict, not a server fault. Reaching
  # here means two concurrent requests raced past an application-level guard —
  # the honest answer is "retry", not "something went wrong".
  rescue_from ActiveRecord::RecordNotUnique, with: :render_conflict

  # Included after the rescue_from declarations above: Rails matches handlers
  # from the most recently registered backwards, so Pundit's handlers must be
  # registered last to win over the catch-all StandardError handler.
  include Authorizable

  private

  def render_error(code:, message:, status:, details: nil)
    body = { error: { code: code, message: message } }
    body[:error][:details] = details if details.present?

    render json: body, status: status
  end

  def render_not_found(_error = nil)
    # Deliberately does not echo which record was missing: that would let an
    # unauthorised caller probe for the existence of other users' resources.
    render_error(code: "not_found", message: "Resource not found", status: :not_found)
  end

  def render_unprocessable(error)
    render_error(
      code: "validation_failed",
      message: "The request could not be processed",
      status: :unprocessable_content,
      details: error.record.errors.to_hash(true)
    )
  end

  def render_conflict(error)
    # The constraint name can expose schema detail, so it is logged rather than
    # returned.
    Rails.logger.warn(event: "unique_violation", message: error.message)

    render_error(
      code: "conflict",
      message: "The request conflicted with a concurrent change. Please retry.",
      status: :conflict
    )
  end

  def render_bad_request(error)
    render_error(code: "bad_request", message: error.message, status: :bad_request)
  end

  def render_internal_error(error)
    # Log the cause, return nothing about it. Stack traces and exception
    # messages routinely contain table names, queries and secrets.
    Rails.logger.error(
      event: "unhandled_exception",
      class: error.class.name,
      message: error.message,
      backtrace: error.backtrace&.first(10)
    )

    render_error(
      code: "internal_error",
      message: "Something went wrong",
      status: :internal_server_error
    )
  end
end
