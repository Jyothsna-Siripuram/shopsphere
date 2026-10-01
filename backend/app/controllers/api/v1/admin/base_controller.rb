module Api
  module V1
    module Admin
      # Shared base for the administrative namespace.
      #
      # The role gate here is a coarse first filter, NOT the authorization
      # itself: each action still calls `authorize`, and `verify_authorized`
      # still fails the request if it does not. Relying on the namespace alone
      # would mean one mis-nested controller silently exposes an admin endpoint,
      # and would leave per-record rules — such as an administrator being unable
      # to change their own role — unenforced.
      class BaseController < ApplicationController
        before_action :require_admin!

        private

        def require_admin!
          return if current_user&.admin?

          render_error(
            code: "forbidden",
            message: "You are not allowed to perform this action",
            status: :forbidden
          )
        end
      end
    end
  end
end
