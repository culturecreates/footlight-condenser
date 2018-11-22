class EventsController < ApplicationController

  # Main API call for portal to get the index of events
  # GET /websites/:seedurl/events
  def index
    @events = []
    event_rdfs_class_id = RdfsClass.where(name:"Event")

    titles = get_event_titles [Time.now..Time.now.next_year]
    #remove blank titles which can happen with multiple languages
    titles_hash = titles.map {|title| [title[0],title[1]] if !title[1].blank? }.to_h

    photos = get_event_photos [Time.now..Time.now.next_year]
    photos_hash = photos.to_h

    event_status = get_event_status
    uris_with_problems = event_status.select{|event| event[1] == "problem"}.map{|event| event = event[0]}
    uris_to_review = event_status.select{|event| event[1] == "initial"}.map{|event| event = event[0]}
    uris_updated = event_status.select{|event| event[1] == "updated"}.map{|event| event = event[0]}

    photos_hash.each do |photo|
        uri = photo[0]
        if !titles_hash[uri].include?("error:")  #prevent sending events that have failed being scrapped
          @events << {rdf_uri: uri,
                      statements_status:
                            {to_review: uris_to_review.include?(uri),
                               updated: uris_updated.include?(uri),
                               problem: uris_with_problems.include?(uri)},
                    photo: photo[1],
                    title: titles_hash[uri]}
        end
    end
    @total_events = @events.count
  end





  private

    def get_event_titles archive_date_range = [time.now - 10.years..time.now + 10.years]
      return Statement.joins({source: [:property, :website]},:webpage).where({sources:{selected: true, properties:{label: "Title", rdfs_class: 1}, websites:  {seedurl: params[:seedurl]}, webpages: {archive_date: archive_date_range}  }  }  ).pluck(:rdf_uri, :cache, "sources.language", :url)
    end

    def get_event_photos archive_date_range = [time.now - 10.years..time.now + 10.years]
      return Statement.joins({source: [:property, :website]},:webpage).where({sources:{selected: true, properties:{label: "Photo", rdfs_class: 1},websites:  {seedurl:  params[:seedurl]},webpages: {archive_date: archive_date_range}   }  }  ).order(:created_at).pluck(:rdf_uri, :cache)
    end

    def get_event_status
      return Statement.joins({webpage: :website},:source).where(webpages:{websites: {seedurl: params[:seedurl]}}).where(sources: {selected: true}).pluck(:rdf_uri, :status).uniq
    end




end
