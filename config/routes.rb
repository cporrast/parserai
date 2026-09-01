Rails.application.routes.draw do
  root "tasks#index"

  resources :tasks, only: :index

  resources :projects, except: :destroy do
    resources :scrape_runs, only: %i[new create] do
      post :suggest_schema, on: :collection
      post :suggest_rules, on: :collection
      post :test_rules, on: :collection
      post :prefetch_setup, on: :collection
    end
    resources :chat_messages, only: :create
  end

  resources :scrape_runs, only: %i[show edit update] do
    post :execute, on: :member
  end
  resources :scrape_executions, only: :show do
    post :cancel, on: :member
  end
  resources :scrape_sources, only: :show
  resources :llm_requests, only: :show
  resources :async_operations, only: %i[show destroy]
  resources :extraction_outputs, only: :show do
    get :export, on: :member
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
