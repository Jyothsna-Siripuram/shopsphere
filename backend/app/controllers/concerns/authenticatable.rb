module Authenticatable
  extend ActiveSupport::Concern

  included do
    # Secure by default: every controller requires authentication unless it
    # explicitly opts out with `skip_before_action :authenticate_user!`.
    #
    # The inverse — opting in per controller — means a forgotten line silently
    # ships an unauthenticated endpoint, and nothing fails to reveal it.
    before_action :authenticate_user!
  end

  private

  def authenticate_user!
    current_user || render_unauthorized
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = resolve_current_user
  end

  def signed_in?
    current_user.present?
  end

  def resolve_current_user
    token = bearer_token
    return nil if token.blank?

    user = User.find_by(id: Auth::AccessToken.subject_id(token))
    # A token issued before suspension must stop working immediately, which is
    # exactly why status is read from the database rather than a token claim.
    return nil unless user&.active_status?

    user
  rescue Auth::AccessToken::InvalidToken
    nil
  end

  def bearer_token
    header = request.headers["Authorization"]
    return nil if header.blank?

    # Only accept the Bearer scheme, and only a well-formed value.
    header[/\ABearer (.+)\z/, 1]
  end

  def render_unauthorized
    render json: {
      error: { code: "unauthorized", message: "Authentication is required" }
    }, status: :unauthorized
  end
end
