Rails.application.routes.draw do
  # Lightweight liveness probe for process-level load balancers.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
    end
  end
end
