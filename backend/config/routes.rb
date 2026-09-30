Rails.application.routes.draw do
  # Lightweight liveness probe for process-level load balancers.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"

      namespace :auth do
        # Workflow endpoints rather than REST resources: registering, logging in
        # and refreshing are actions on a session, not CRUD on a record, and
        # naming them for what they do keeps the contract obvious.
        post "register", to: "registrations#create"
        post "login",    to: "sessions#create"
        post "logout",   to: "sessions#destroy"
        post "refresh",  to: "tokens#create"
      end
    end
  end
end
