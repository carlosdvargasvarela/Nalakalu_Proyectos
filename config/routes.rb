Rails.application.routes.draw do
  namespace :admin do
    resources :project_types do
      resources :field_definitions, except: [:index, :show]
      resources :stage_templates, except: [:index, :show]
    end
  end
  resources :projects

  root "projects#index"
end
