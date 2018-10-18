class EventsController < ApplicationController

  # GET /websites/:seedurl/events
  def index

    require 'will_paginate/array'
    per_page = params[:per_page]
    per_page ||= 200

    @events = []

    event_rdfs_class_id = RdfsClass.where(name:"Event")


    titles = Statement.joins({source: [:property, :website]},:webpage).where({sources:{selected: true, properties:{label: "Title", rdfs_class: 1},websites:  {seedurl: params[:seedurl]}  }  }  ).pluck(:rdf_uri,:cache, "sources.language")
    titles_hash = titles.map {|title| [title[0],title[1]] if !title[1].blank? }.to_h
    photos_hash = Statement.joins({source: [:property, :website]},:webpage).where({sources:{selected: true, properties:{label: "Photo", rdfs_class: 1},websites:  {seedurl:  params[:seedurl]}  }  }  ).order(:created_at).pluck(:rdf_uri, :cache).to_h


    uris_with_problems = Statement.joins({webpage: :website},:source).where(webpages:{websites: {seedurl: params[:seedurl]}}).where(sources: {selected: true}).where(status: "problem").pluck(:rdf_uri).uniq
    uris_to_review = Statement.joins({webpage: :website},:source).where(webpages:{websites: {seedurl: params[:seedurl]}}).where(sources: {selected: true}).where(status: "initial").pluck(:rdf_uri).uniq
    uris_updated = Statement.joins({webpage: :website},:source).where(webpages:{websites: {seedurl: params[:seedurl]}}).where(sources: {selected: true}).where(status: "updated").pluck(:rdf_uri).uniq


    photos_hash.each do |photo|
        @events << {rdf_uri: photo[0], statements_status: {to_review: uris_to_review.include?(photo[0]), updated: uris_updated.include?(photo[0]), problem: uris_with_problems.include?(photo[0])}, photo: photo[1], title: titles_hash[photo[0]]  }
    end

    @total_events = @events.count

# data structure
          #     {"rdf_uri":"adr:canadianstage-com_full-light_18-19-season",
          #       "statements_status":{"initial":9,"missing":3,"ok":0,"updated":0,"problem":0},
          #       "photo":"https://canadianstage.com/ArticleMedia/Images/18.19/shows/full-light-of-day-updated-large.jpg",
          #       "title":"The Full Light of Day"}



    #use helpers in resources_helper
  #   event_uris = helpers.get_uris params[:seedurl], "Event"
  #   event_uris.each do |event_uri|
  #     @events << {rdf_uri: event_uri }
  #   end
  #
  #   @total_events = event_uris.count
  #   #### PAGINATE
  #   @events = @events.paginate(page:params[:page], per_page: per_page)
  #
  #   @events.each do |event|
  #     _statements = []
  #     _webpages = Webpage.where(rdf_uri: event[:rdf_uri]).includes([:statements,{:statements => {:source => :property}}])
  # #  _webpages = Webpage.where(rdf_uri: event[:rdf_uri])
  #     _webpages.each do |webpage|
  #       webpage.statements.each do |statement|
  #         _statements << statement
  #       end
  #     end
  #
  #     #alternative is to do 2 queries: pluck :title from all statements related to seedurl and with property title, second for photo
  #     if !_statements.blank?
  #       event[:statements_status] = helpers.calculate_resource_status _statements
  #       _statements.each do |s|
  #          if s.source.property.label == "Title"  && s.source.selected
  #            event[:title] = s.cache if s.source.language == "en"
  #            event[:title] = s.cache if s.source.language == "fr" && event[:title].blank?
  #         end
  #         event[:photo] = s.cache if s.source.property.label == "Photo" && s.source.selected
  #       end
  #     end
  #   end

  end




end
