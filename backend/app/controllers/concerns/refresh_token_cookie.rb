module RefreshTokenCookie
  extend ActiveSupport::Concern

  COOKIE_NAME = :shopsphere_refresh_token

  private

  def set_refresh_token_cookie(raw_token)
    cookies[COOKIE_NAME] = {
      value: raw_token,
      # The whole point: JavaScript cannot read this, so an XSS payload cannot
      # exfiltrate the long-lived credential.
      httponly: true,
      # Never transmitted over plaintext outside local development.
      secure: !Rails.env.local?,
      # A cross-site POST will not carry this cookie, which is the primary CSRF
      # mitigation. app.example.com -> api.example.com stays same-site because
      # SameSite compares registrable domain, not origin.
      same_site: :lax,
      # Scoped to the auth endpoints, so it is not attached to ordinary API
      # traffic that has no use for it.
      path: "/api/v1/auth",
      expires: RefreshToken::LIFETIME.from_now
    }
  end

  def refresh_token_from_cookie
    cookies[COOKIE_NAME]
  end

  def delete_refresh_token_cookie
    # Attributes must match those used when setting it or the browser keeps the
    # original cookie.
    cookies.delete(COOKIE_NAME, path: "/api/v1/auth", same_site: :lax)
  end

  # Defence in depth behind SameSite. A browser that predates SameSite, or a
  # future relaxation to SameSite=None for a cross-site deployment, would
  # otherwise leave the refresh endpoint CSRF-exposed.
  def verify_request_origin!
    origin = request.headers["Origin"]
    return true if origin.blank?
    return true if Rails.configuration.x.allowed_origins.include?(origin)

    render_error(
      code: "forbidden_origin",
      message: "Request origin is not allowed",
      status: :forbidden
    )
    false
  end
end
