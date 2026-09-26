module Api
  module V1
    class HealthController < ApplicationController
      def show
        Health::ReadinessCheck.call

        render json: { data: { status: "ok" } }
      rescue Health::ReadinessCheck::Unavailable
        render json: { error: { code: "service_unavailable", message: "Service temporarily unavailable" } }, status: :service_unavailable
      end
    end
  end
end
