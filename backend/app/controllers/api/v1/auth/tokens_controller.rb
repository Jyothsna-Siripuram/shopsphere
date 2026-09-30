module Api
  module V1
    module Auth
      # POST /api/v1/auth/refresh
      #
      # Reads the refresh token from the HttpOnly cookie rather than the request
      # body, so the SPA never handles the value and an XSS payload cannot reach
      # it.
      class TokensController < BaseController
        before_action :verify_request_origin!

        def create
          pair = ::Auth::RotateRefreshToken.call(
            raw_token: refresh_token_from_cookie,
            user_agent: request.user_agent,
            client_ip: request.remote_ip
          )

          set_refresh_token_cookie(pair.refresh_token)
          render json: session_payload(pair.refresh_record.user, pair.access_token), status: :ok
        rescue ::Auth::RotateRefreshToken::InvalidRefreshToken
          # Reuse detection and an ordinary expiry return the same response.
          # Telling an attacker that their replay was detected only teaches them
          # to avoid it; the family has already been revoked either way.
          delete_refresh_token_cookie

          render_error(
            code: "invalid_refresh_token",
            message: "The session could not be refreshed",
            status: :unauthorized
          )
        end
      end
    end
  end
end
