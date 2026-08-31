Rails.application.routes.draw do
  devise_for :users, skip: [:registrations]
  devise_scope :user do
    get "cuenta", to: "devise/registrations#edit", as: "edit_user_registration"
    put "cuenta", to: "devise/registrations#update", as: "user_registration"
  end
  patch "cuenta/preferencias", to: "user_preferences#update", as: :user_preferences
  get "help/*topic", to: "help#show", as: :help_topic
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
      resources :duration_profiles, except: [:index, :show] do
        patch :reorder, on: :collection
      end
      resources :event_types, except: [:index, :show] do
        patch :reorder, on: :collection
      end
      resources :log_entry_types, except: [:index, :show]
      resources :responsible_types, except: [:index, :show]
    end
    resources :responsibles
    resources :project_type_associations
  end

  get "projects/seguimiento", to: "projects#tracker", as: :tracker_projects
  patch "projects/bulk_assign_responsible", to: "projects#bulk_assign_responsible", as: :bulk_assign_responsible_projects
  get "projects/tipo/:slug", to: "projects#index", as: :project_type_projects
  resources :projects do
    member { post :apply_auto_duration }
    resources :log_entries, only: [:create, :destroy]
    resources :project_responsibles, only: [:create, :destroy]
    resources :project_associations, only: [:create, :destroy]
    resources :events, only: [:create, :update, :destroy]
  end

  resources :imports, only: [:new, :create] do
    collection { post :preview }
  end
  get "imports/template", to: "imports#template", as: :template_imports

  root "projects#index"
end
