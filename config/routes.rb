Rails.application.routes.draw do

  root   'websites#index'


  resources :statements do
    collection do
      get 'refresh_rdf_uri', 'event', 'webpage','refresh_webpage'
    end
    member do
      get 'refresh'
    end
  end
  resources :sources do
    collection do
      get 'website'
    end
    member do
      get 'test_scrape'
    end
  end
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
