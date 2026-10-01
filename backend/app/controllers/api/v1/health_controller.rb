module Api
  module V1
    class HealthController < ApplicationController
      # Load balancer and container health probes cannot authenticate. The
      # response carries no information beyond up/down, so this is safe to
      # expose; the readiness check deliberately does not name which dependency
      # is unavailable.
      skip_before_action :authenticate_user!
      # No record and no caller to authorize; the response carries only up/down.
      skip_after_action :verify_authorized

      def show
        Health::ReadinessCheck.call

        render json: { data: { status: "ok" } }
      rescue Health::ReadinessCheck::Unavailable
        render json: { error: { code: "service_unavailable", message: "Service temporarily unavailable" } }, status: :service_unavailable
      end
    end
  end
end
