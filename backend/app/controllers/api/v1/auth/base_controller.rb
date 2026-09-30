module Api
  module V1
    module Auth
      # Shared behaviour for the unauthenticated auth endpoints.
      #
      # These are the only controllers that legitimately skip authentication,
      # which is why the skip lives here once rather than being repeated — and
      # forgotten, or copied somewhere it does not belong.
      class BaseController < ApplicationController
        include RefreshTokenCookie

        skip_before_action :authenticate_user!

        private

        def issue_session(user)
          pair = ::Auth::IssueTokenPair.call(
            user: user, user_agent: request.user_agent, client_ip: request.remote_ip
          )
          set_refresh_token_cookie(pair.refresh_token)
          pair
        end

        def session_payload(user, access_token)
          {
            data: {
              user: UserSerializer.call(user),
              access_token: access_token,
              token_type: "Bearer",
              # Seconds, so the SPA can schedule a silent refresh rather than
              # parsing the JWT itself.
              expires_in: ::Auth::AccessToken::LIFETIME.to_i
            }
          }
        end

        # Registration, login and refresh failures all return the same shape, so
        # a client never has to branch on which step failed.
        def render_invalid_credentials
          render_error(
            code: "invalid_credentials",
            message: "Email or password is incorrect",
            status: :unauthorized
          )
        end
      end
    end
  end
end
