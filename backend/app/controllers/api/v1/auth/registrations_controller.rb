module Api
  module V1
    module Auth
      class RegistrationsController < BaseController
        def create
          user = User.new(registration_params)
          # Never assignable from request parameters, regardless of what the
          # permitted list below happens to contain.
          user.role = "customer"

          if user.save
            pair = issue_session(user)
            render json: session_payload(user, pair.access_token), status: :created
          else
            render_error(
              code: "validation_failed",
              message: "The account could not be created",
              status: :unprocessable_content,
              details: user.errors.to_hash(true)
            )
          end
        end

        private

        # The allowlist that stops privilege escalation through a crafted body.
        # Explicitly assigning role above is the second layer, in case this list
        # is ever widened carelessly.
        def registration_params
          params.expect(user: [ :email, :password, :password_confirmation, :first_name, :last_name ])
        end
      end
    end
  end
end
