module Api
  module V1
    module Admin
      class UsersController < BaseController
        before_action :set_user, only: %i[show update]

        def index
          users = policy_scope(User).order(:id)

          render json: { data: users.map { |user| UserSerializer.call(user) } }
        end

        def show
          render json: { data: UserSerializer.call(@user) }
        end

        def update
          # Role and status changes carry their own rules beyond "is an admin":
          # an administrator must not demote or suspend themselves, or the last
          # remaining admin could lock everyone out of the system.
          authorize @user, :change_role? if role_change?
          authorize @user, :suspend? if suspension?

          if @user.update(user_params)
            render json: { data: UserSerializer.call(@user) }
          else
            render_error(
              code: "validation_failed",
              message: "The user could not be updated",
              status: :unprocessable_content,
              details: @user.errors.to_hash(true)
            )
          end
        end

        private

        def set_user
          @user = policy_scope(User).find(params[:id])
          authorize @user
        end

        def user_params
          params.expect(user: policy(@user).permitted_attributes)
        end

        def role_change?
          user_params.key?(:role) && user_params[:role] != @user.role
        end

        def suspension?
          user_params.key?(:status) && user_params[:status] != @user.status
        end
      end
    end
  end
end
