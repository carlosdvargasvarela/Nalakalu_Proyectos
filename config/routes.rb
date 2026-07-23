Rails.application.routes.draw do
  devise_for :users
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest.json" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker.js" => "rails/pwa#service_worker", as: :pwa_service_worker

  namespace :admin do
    resources :project_types do
      resources :field_definitions, except: [:index, :show]
      resources :stage_templates, except: [:index, :show]
    end
  end
  resources :projects do
    resources :project_stages, only: [:edit, :update]
  end

  root "projects#index"
end
