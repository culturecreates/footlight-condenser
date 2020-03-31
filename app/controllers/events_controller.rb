class EventsController < ApplicationController

  # Main API call for portal to get the index of events
  # GET /websites/:seedurl/events
  def index
    params[:startDate]  # "2018-01-01"
    params[:endDate]   # "2021-01-01"

    
    @events = []
    event_rdfs_class_id = RdfsClass.where(name:"Event")

    start_date = Time.now
    end_date = Time.now.next_year + 6.months

    if params[:startDate] 
      begin
        start_date = Date.parse(params[:startDate])
      rescue => exception
        logger.error("Invalid start_date parameter: #{exception.inspect}")
      end
    end

    if params[:endDate] 
      begin
        end_date = Date.parse(params[:endDate])
      rescue => exception
        logger.error("Invalid end_date parameter: #{exception.inspect}")
      end
    end

    time_span = [start_date..end_date]


    website_events = get_events(time_span)

    titles = get_event_titles(website_events)
    #remove blank titles which can happen with multiple languages
    titles_hash = titles.map {|title| [title[0],title[1]] if !title[1].blank? }.to_h

    photos = get_event_photos(website_events)
    photos_hash = photos.to_h

    dates = get_event_dates(website_events)
    dates.map! { |array| [array[0],helpers.parse_date_string_array(array[1])]}
    dates_hash = dates.to_h

    archive_dates = get_archive_dates 
    archive_dates_hash = archive_dates.to_h

    uris_with_problems = website_events.select{|s| s.status == "problem"}.map{|s| s = s.webpage.rdf_uri}
    uris_to_review =  website_events.select{|s| s.status == "initial"}.map{|s| s = s.webpage.rdf_uri}
    uris_updated = website_events.select{|s| s.status == "updated"}.map{|s| s = s.webpage.rdf_uri}

    uris_title_publishable = get_uris_publishable "Title", website_events
    uris_dates_publishable = get_uris_publishable "Dates", website_events
    uris_location_publishable = get_uris_publishable "Location", website_events

    photos_hash.each do |photo|
        uri = photo[0]
        titles_hash[uri] = "Error" if titles_hash[uri].include?("error:")  #prevent sending events that have failed being scrapped
        @events << {rdf_uri: uri,
                    statements_status:
                          {to_review: uris_to_review.include?(uri),
                             updated: uris_updated.include?(uri),
                             problem: uris_with_problems.include?(uri),
                             publishable: uris_title_publishable.include?(uri) && uris_dates_publishable.include?(uri) && uris_location_publishable.include?(uri) },
                  photo: photo[1],
                  title: titles_hash[uri],
                  date: dates_hash[uri] || helpers.patch_invalid_date,
                  archive_date: archive_dates_hash[uri]
                }
    end

    @events.sort_by! {|item| item[:archive_date]}
    @total_events = @events.count
  end





  private

    def get_events archive_date_range = [Time.now - 10.years..Time.now + 10.years]
      return Statement.joins({source: [:property, :website]},:webpage).where({sources:{selected: true, properties:{rdfs_class: 1}, websites:  {seedurl: params[:seedurl]}, webpages: {archive_date: archive_date_range}  }  }  ).includes([{source: [:property, :website]},:webpage])
    end

    def get_event_titles events_relation
      return events_relation.select { |s| s.source.property.label == "Title"}.map{|s| [s.webpage.rdf_uri, s.cache, s.source.language, s.webpage.url]}
    end

    def get_event_photos events_relation
      return events_relation.select { |s| s.source.property.label == "Photo"}.map{|s| [s.webpage.rdf_uri, s.cache]}
     end

    def get_event_dates events_relation
      return events_relation.select { |s| s.source.property.label == "Dates"}.map{|s| [s.webpage.rdf_uri, s.cache]}
     end

    def get_archive_dates
      return Webpage.joins(:website).where(rdfs_class: 1, websites: {seedurl: params[:seedurl]}).order(:archive_date).pluck(:rdf_uri, :archive_date)
    end



    def get_uris_publishable property, events_relation
      #TODO: This is misleading for bilingual sites which will have a publishable title if either en or fr meets the conditions of ok || updated
      #keep only those with status  OK || updated
      return events_relation.select { |s| s.source.property == property}.select { |s| (s.status == "ok" || s.status == "updated") && (!s.cache.blank? && s.cache != "[[]]" && !s.cache.include?("error") )}.map{|s| s.webpage.rdf_uri}.uniq
    end
  

end
