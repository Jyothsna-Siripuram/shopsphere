module Api
  module V1
    module Auth
      class SessionsController < BaseController
        # Logout must know who is calling, so it is the one action here that
        # requires a valid access token.
        before_action :authenticate_user!, only: :destroy

        def create
          user = ::Auth::AuthenticateUser.call(
            email: login_params[:email], password: login_params[:password]
          )
          return render_invalid_credentials if user.nil?

          user.update_column(:last_login_at, Time.current)
          pair = issue_session(user)

          render json: session_payload(user, pair.access_token), status: :ok
        end

        # Logout revokes the presented refresh token only, not every session, so
        # signing out on a laptop does not sign the customer out on their phone.
        # Revoking every device is a separate, explicit action.
        def destroy
          token = RefreshToken.find_by_raw_token(refresh_token_from_cookie)
          token.revoke!("logout") if token&.user_id == current_user.id

          delete_refresh_token_cookie

          head :no_content
        end

        private

        def login_params
          params.expect(user: [ :email, :password ])
        end
      end
    end
  end
end
