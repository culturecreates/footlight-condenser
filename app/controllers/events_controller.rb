class EventsController < ApplicationController

  # GET /websites/:seedurl/events
  def index

    require 'will_paginate/array'
    per_page = params[:per_page]
    per_page ||= 200

    @events = []

    #use helpers in resources_helper
    event_uris = helpers.get_uris params[:seedurl], "Event"
    event_uris.each do |event_uri|
      @events << {rdf_uri: event_uri }
    end

    @total_events = event_uris.count
    #### PAGINATE
    @events = @events.paginate(page:params[:page], per_page: per_page)

    @events.each do |event|
      _statements = []
      #query
      _webpages = Webpage.where(rdf_uri: event[:rdf_uri]).includes([:statements,{:statements => {:source => :property}}])
  #  _webpages = Webpage.where(rdf_uri: event[:rdf_uri])

      _webpages.each do |webpage|
        webpage.statements.each do |statement|
          _statements << statement
        end
      end


      if !_statements.blank?
        event[:statements_status] = helpers.calculate_resource_status _statements
        _statements.each do |s|
           if s.source.property.label == "Title"  && s.source.selected
             event[:title] = s.cache if s.source.language == "en"
             event[:title] = s.cache if s.source.language == "fr" && event[:title].blank?
          end
          event[:photo] = s.cache if s.source.property.label == "Photo" && s.source.selected
        end
      end


    end


  end




end
