Rails.application.routes.draw do

  root 'websites#index'


  resources :statements do
    collection do
      get  'refresh_rdf_uri', 'webpage','refresh_webpage'
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
  resources :webpages do
    collection do
      get 'website'
    end
  end


  resources :websites do
    collection do
      get 'events','places'
    end
  end


### eventually replace these with resouces websites, param: :seedurl

defaults format: :json do
  get 'websites/:seedurl/resources',
      to: "resources#index",
      constraints: {seedurl: /[^\/]+/ }

  get 'websites/:seedurl/events',
      to: "events#index",
      constraints: {seedurl: /[^\/]+/ }

  get 'resources/:rdf_uri',
      to: "resources#show",
      constraints: {rdf_uri: /[^\/]+/ },
      as: :show_resources

  get 'resources/:rdf_uri/reviewed_all',
      to: "resources#reviewed_all",
      constraints: {rdf_uri: /[^\/]+/ },
      as: :reviewed_all_resources
end




  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
