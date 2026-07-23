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
    resources :installers
  end

  get "projects/seguimiento", to: "projects#tracker", as: :tracker_projects
  resources :projects

  root "projects#index"
end
