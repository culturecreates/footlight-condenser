Rails.application.routes.draw do

  get 'structured_data/event_markup'

  root 'websites#index'


  resources :statements do
    collection do
      get  'refresh_rdf_uri', 'webpage','refresh_website_events'
      patch 'refresh_webpage'
    end
    member do
      patch 'activate', 'add_linked_data','remove_linked_data','refresh'
    end
  end

  resources :sources do
    collection do
      get 'website'
    end
  end

  resources :properties
  resources :rdfs_classes
  resources :webpages do
    collection do
      post 'create_api'
      patch 'refresh'
    end
  end


  resources :websites do
    collection do
      get 'events','places', 'test_api'
    end
  end


### eventually replace these with resouces websites, param: :seedurl

###   constraints: {seedurl: /[^\/]+/ }

  get 'websites/:seedurl/resources',
      to: "resources#index",
      as: :website_all_resources


  get 'websites/:seedurl/events',
      to: "events#index",
      as: :website_events


  get 'resources/:rdf_uri',
      to: "resources#show",
      as: :show_resources

  patch 'resources/:rdf_uri/reviewed_all',
      to: "resources#reviewed_all",
      as: :reviewed_all_resources







  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
