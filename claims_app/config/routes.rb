Rails.application.routes.draw do
  root "imports#new"

  resource :import, only: [:new, :create, :destroy]
  post "import/documents", to: "imports#create_documents", as: :import_documents
  post "adjudicate", to: "imports#adjudicate", as: :adjudicate
  resources :claims, only: [:index, :show]
  get "activities/unlinked", to: "activities#unlinked", as: :unlinked_activities

  get "up" => "rails/health#show", as: :rails_health_check
end
