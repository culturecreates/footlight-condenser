Rails.application.routes.draw do
  resources :sources
  resources :statements
  resources :statuses
  resources :predicates
  resources :webpages
  resources :object_classes
  resources :websites
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
