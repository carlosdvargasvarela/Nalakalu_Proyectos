Rails.application.routes.draw do
  devise_for :users, skip: [:registerable]
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest.json" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker.js" => "rails/pwa#service_worker", as: :pwa_service_worker

  namespace :admin do
    resources :users
    resources :project_types do
      resources :field_definitions, except: [:index, :show] do
        patch :reorder, on: :collection
      end
      resources :stage_templates, except: [:index, :show] do
        patch :reorder, on: :collection
      end
      resources :log_entry_types, except: [:index, :show]
      resources :responsible_types, except: [:index, :show]
    end
    resources :responsibles
  end

  get "projects/seguimiento", to: "projects#tracker", as: :tracker_projects
  patch "projects/bulk_assign_responsible", to: "projects#bulk_assign_responsible", as: :bulk_assign_responsible_projects
  resources :projects do
    resources :log_entries, only: [:create, :destroy]
    resources :project_responsibles, only: [:create, :destroy]
  end

  resources :imports, only: [:new, :create]
  get "imports/template", to: "imports#template", as: :template_imports

  root "projects#index"
end
