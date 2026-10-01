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

      # Singular resource: the acting user's own profile. Without an id in the
      # path there is no way to address another customer's record at all.
      resource :profile, only: %i[show update], controller: "profiles"

      resources :addresses, only: %i[index show create update destroy]

      namespace :admin do
        resources :users, only: %i[index show update]
      end
    end
  end
end
