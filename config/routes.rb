Rails.application.routes.draw do
  
  ##
  # API Section used by Footlight Console
  # For resource collections, the API calls using implicit actions (like get) are listed in comments.
  # and admin webpage actions moved to seperate lines and commented with "Internal Webpages only"

  require 'sidekiq/web'
  mount Sidekiq::Web => '/sidekiq'

  get "websites/wring", to: "wringer_compatibility#show", as: :wring_websites

  resources :websites do
    # API: get /websites 
    member do
      post :activate_anyway
    end
    collection do
      get 'events'         # Internal Webpages Only
      get 'places'         # Internal Webpages Only
      get 'test_api'       # Internal Webpages Only
      delete 'delete_all_statements'     # Internal Webpages Only
      delete 'delete_all_webpages'       # Internal Webpages Only
      delete 'delete_all_event_webpages' # Internal Webpages Only
    end
  end

  namespace :distillator do
    get :shadow_report, to: "shadow_reports#index", as: :shadow_report
    get "shadow_report/:id", to: "shadow_reports#show", as: :shadow_report_site
    resources :transition_checks, only: [:create]

    resources :cache, only: [:index, :show], controller: "cache" do
      collection do
        get :preview
        get :compare
        post :fetch
      end

      member do
        get :raw
        get :raw_view
        get :wring_json
        get :wring_json_view
      end
    end
  end

  get "/condenser/cache", to: "distillator/cache#index", as: :condenser_cache_index
  get "/condenser/cache/compare", to: "distillator/cache#compare", as: :condenser_cache_compare

  get 'websites/:seedurl/resources',
      to: "resources#index",
      as: :website_all_resources

  get 'websites/:seedurl/events',
      to: "events#index",
      as: :website_events

  get 'websites/:seedurl/events_by_property',
      to: "events#index_by_property",
      as: :website_events_by_property

  get 'events/:id/pipeline_health',
      to: "events#pipeline_health",
      as: :event_pipeline_health

  get 'resources/:rdf_uri',
      to: "resources#show",
      as: :show_resources

  get 'resources',
      to: "resources#uri",
      as: :uri_resources

  get 'recon',
      to: "resources#recon",
      as: :recon_resources

  delete 'resources/delete_uri',
      to: "resources#delete_uri",
      as: :destroy_resource_uri

  delete 'resources/:rdf_uri',
      to: "resources#destroy",
      as: :destroy_resources
      


  post 'resources',
      to: "resources#create_resource",
      as: :create_resource

  patch 'resources/:rdf_uri/reviewed_all',
      to: "resources#reviewed_all",
      as: :reviewed_all_resources

  resources :statements do
    member do
      patch 'activate'               # API
      patch 'activate_individual'    # API
      patch 'deactivate_individual'  # API
      patch 'add_linked_data'        # API
      patch 'remove_linked_data'     # API
      get 'refresh'                  # Internal Webpages Only
      patch 'refresh'                # Internal Webpages Only
    end
    collection do
      get 'webpage'                  # Internal Webpages Only
      get 'search_name'              # When manually adding links in Console
      patch 'refresh_webpage'        # Internal Webpages Only
      patch 'refresh_rdf_uri'        # Internal Webpages Only
      post 'batch_update'            # Internal Webpages Only
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

  # options
  get 'options', to: 'options#index', as: :options
  get 'options/wringer/:target', to: 'options#wringer', as: :set_wringer
  get 'options/set_dsl_trace/:state', to: 'options#set_dsl_trace', as: :set_dsl_trace_options
  get 'options/set_trace_visibility/:state',
      to: 'options#set_trace_visibility',
      as: :set_trace_visibility_options
  get 'options/set_trace_code_length/:length',
      to: 'options#set_trace_code_length',
      as: :set_trace_code_length_options
  get 'options/set_trace_output_length/:length',
      to: 'options#set_trace_output_length',
      as: :set_trace_output_length_options
  post "options/trace_view_mode/:mode",
       to: "options#set_trace_view_mode",
       as: :set_trace_view_mode
  post "options/trace_preset/:preset",
       to: "options#set_trace_preset",
       as: :set_trace_preset

  post   'options', to: 'options#update'
  patch  'options', to: 'options#update'

  # Dashboard metrics
  get "/dashboard_metrics", to: "dashboard_metrics#index"
  get "/dashboard_metrics/broken", to: "dashboard_metrics#broken"

  ##
  # Admin section only used for admin webpages
  # These actions are not used by external Footlight Console APIs
  #
  #
  root 'websites#index'

  resources :jsonld_outputs

  resources :batch_jobs do
    collection do
      get 'add_webpages'
      get 'refresh_webpages'
      get 'refresh_upcoming_events'
      get 'check_for_new_webpages'
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

  get 'graphs/website/:seedurl',
    to: 'graphs#website',
    as: :graphs_website

  get 'graphs/website_queue/:seedurl',
    to: 'graphs#website_queue',
    as: :graphs_website_queue

  get 'graphs/webpage/event-artsdata',
    to: 'graphs#webpage_event_artsdata',
    as: :graphs_webpage_event_artsdasta

  get 'graphs/webpage/event',
    to: 'graphs#webpage_event',
    as: :graphs_webpage_event




  resources :reports do
    collection do
      get 'source' 
    end
  end

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
