Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :billing_events, only: :index

      resources :plans, only: %i[index show create] do
        post :archive, on: :member
      end

      resources :subscriptions, only: %i[index show create] do
        member do
          post :cancel
          post :undo_cancel
          post :pause
          post :resume
          get :state_transitions
        end
      end

      resources :customers, only: %i[index show create] do
        resources :payment_methods, only: :create do
          post :make_default, on: :member
        end
        resources :credit_ledger_entries, only: %i[index create]
      end

      post "webhooks/stripe", to: "webhooks#stripe"
      resources :webhook_events, only: %i[index show] do
        post :reprocess, on: :member
      end

      if Rails.configuration.x.simulator_enabled
        namespace :simulator do
          resource :clock, only: :show do
            post :advance
            post :reset
          end
          resources :test_cards, only: :index
          resources :events, only: %i[index create] do
            post :deliver, on: :member
          end
        end
      end
    end
  end
end
