module Api
  module V1
    # The acting user's own record. A singular resource, so there is no id in
    # the path and therefore no way to address someone else's profile at all.
    class ProfilesController < ApplicationController
      def show
        authorize current_user, :show?

        render json: { data: UserSerializer.call(current_user) }
      end

      def update
        authorize current_user, :update?

        if current_user.update(profile_params)
          render json: { data: UserSerializer.call(current_user) }
        else
          render_error(
            code: "validation_failed",
            message: "The profile could not be updated",
            status: :unprocessable_content,
            details: current_user.errors.to_hash(true)
          )
        end
      end

      private

      # The permitted list comes from the policy rather than being hardcoded
      # here, so the rule and its allowlist cannot drift apart. A customer
      # editing their own profile can never submit role or status, even though
      # an administrator editing the same model can.
      def profile_params
        params.expect(user: policy(current_user).permitted_attributes)
      end
    end
  end
end
