Rails.application.routes.draw do

  get 'databus/index'
  post 'databus/create'
  
  resources :search_exceptions
  get 'custom/get_comotion_locations'

  get 'structured_data/event_markup'

  root 'websites#index'


  resources :statements do
    collection do
      get  'webpage'
      patch 'refresh_webpage','refresh_rdf_uri'
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
  resources :places

  resources :lists do
    collection do
      get 'add_webpages'
    end
  end

  resources :reports do
    collection do
      get 'source'
    end
  end

  resources :webpages do
    collection do
      post 'create_api'
      patch 'refresh'
    end
  end


  resources :websites do
    collection do
      get 'events','places', 'test_api'
      delete 'delete_all_statements','delete_all_webpages'
    end
  end

  resources :batch_jobs do
    collection do
      get 'add_webpages', 'refresh_webpages'
    end
  end

  get 'graphs/webpage/event',
      to: 'graphs#webpage_event',
      as: :graphs_webpage_event

### eventually replace these with resouces websites, param: :seedurl

###   constraints: {seedurl: /[^\/]+/ }

  get 'websites/:seedurl/resources',
      to: "resources#index",
      as: :website_all_resources


  get 'websites/:seedurl/events',
      to: "events#index",
      as: :website_events

  get 'websites/:seedurl/export',
      to: "export#export",
      as: :export

  get 'resources/:rdf_uri',
      to: "resources#show",
      as: :show_resources

  patch 'resources/:rdf_uri/reviewed_all',
      to: "resources#reviewed_all",
      as: :reviewed_all_resources

  patch 'resources/:rdf_uri/archive',
      to: "resources#archive",
      as: :archive_resources

  delete 'resources/:rdf_uri',
      to: "resources#destroy",
      as: :destroy_resources

  get 'resources/:rdf_uri/webpage_urls',
      to: "resources#webpage_urls"




  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
