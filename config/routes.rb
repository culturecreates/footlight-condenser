Rails.application.routes.draw do
  ##
  # API Section used by Footlight Console
  # For resource collections, the API calls using implicit actions (like get) are listed in comments.
  # and admin webpage actions moved to seperate lines and commented with "Internal Webpages only"

  resources :websites do
    # API: get /websites 
    collection do
      get 'events','places', 'test_api' # Internal Webpages Only
      delete 'delete_all_statements','delete_all_webpages' # Internal Webpages Only
    end
  end

  get 'websites/:seedurl/resources',
      to: "resources#index",
      as: :website_all_resources

  get 'websites/:seedurl/events',
      to: "events#index",
      as: :website_events

  get 'websites/:seedurl/events_by_property',
      to: "events#index_by_property",
      as: :website_events_by_property

  get 'resources/:rdf_uri',
      to: "resources#show",
      as: :show_resources

  delete 'resources/:rdf_uri',
      to: "resources#destroy",
      as: :destroy_resources

  patch 'resources/:rdf_uri/reviewed_all',
      to: "resources#reviewed_all",
      as: :reviewed_all_resources

  resources :statements do
    # API: patch /statements 
    member do
      patch 'activate','activate_individual','deactivate_individual','add_linked_data', 'remove_linked_data' # API
      patch  'refresh' # Internal Webpages Only
    end
    collection do
      get 'webpage' # Internal Webpages Only
      patch 'refresh_webpage', 'refresh_rdf_uri', 'review_all', 'refresh_all' # Internal Webpages Only
      post 'batch_update' # Internal Webpages Only
    end
  end

  resources :sources do
    # API: get /sources
    collection do
      get 'website' # Internal Webpages Only
      post 'copy' # Internal Webpages Only
    end
  end

  resources :properties do
    member do
      patch 'review_all_statements' # API
    end
  end

  ##
  # Admin section only used for admin webpages
  # These actions are not used by external Footlight Console APIs
  #
  #
  root 'websites#index'

  get 'queue/index', 'queue/clear'

  resources :batch_jobs do
    collection do
      get 'add_webpages', 'refresh_webpages', 'refresh_upcoming_events','check_for_new_webpages'
    end
  end

  resources :messages do
    collection do
      post 'webhook'
    end
  end

  get 'databus/index'
  post 'databus/create'
  post 'databus/artsdata'

  resources :search_exceptions

  get 'structured_data/event_markup'

  resources :places
  
  resources :rdfs_classes

  resources :lists do
    collection do
      get 'add_webpages'
    end
  end
 
  resources :webpages do
    collection do
      post 'create_api' # Internal Webpages Only 
      patch 'refresh' # Internal Webpages Only
    end
  end

  get 'graphs/webpage/event',
      to: 'graphs#webpage_event',
      as: :graphs_webpage_event

  resources :reports do
    collection do
      get 'source' 
    end
  end

  get 'graphs/website/:seedurl',
      to: 'graphs#website',
      as: :graphs_website

### eventually replace these with resouces websites, param: :seedurl

###   constraints: {seedurl: /[^\/]+/ }

  get 'websites/:seedurl/export',
      to: "export#export",
      as: :export


  # match 'resources/:rdf_uri' => 'resources#show',
  #   :via => [:get],
  #   constraints: { id: /.+/ }, as: :resource

  patch 'resources/:rdf_uri/archive',
      to: "resources#archive",
      as: :archive_resources

  get 'resources/:rdf_uri/webpage_urls',
      to: "resources#webpage_urls"




  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
