Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :billing_events, only: :index

      if Rails.configuration.x.simulator_enabled
        namespace :simulator do
          resource :clock, only: :show do
            post :advance
            post :reset
          end
        end
      end
    end
  end
end
