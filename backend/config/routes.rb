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

      # Public catalogue. Addressed by slug, so :id carries a slug here — see
      # Product#to_param.
      resources :products, only: %i[index show]
      resources :categories, only: :index

      # Singular for the same reason as profile: the caller's own cart, with no
      # id that could name someone else's.
      resource :cart, only: %i[show destroy] do
        resources :items, only: %i[create update destroy], controller: "cart_items"
      end

      namespace :admin do
        resources :users, only: %i[index show update]
        # Admin routes address products by id: renaming a product must not
        # change the URL an administrator is editing it at.
        resources :products, only: %i[index show create update destroy]
      end
    end
  end
end
