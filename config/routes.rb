Rails.application.routes.draw do
  resources :statements do
    collection do
      get 'refresh_uri', 'event'
    end
  end
  resources :sources
  resources :properties
  resources :rdfs_classes
  resources :webpages
  resources :websites do
    collection do
      get 'events'
    end
  end
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
