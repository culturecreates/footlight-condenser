# Main API call for portal to get the index of events
# GET /websites/:seedurl/events
class EventsController < ApplicationController
  def index
    params[:startDate] # "2018-01-01"
    params[:endDate] # "2021-01-01"

    @events = []

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

    titles = get_event_titles time_span
    # remove blank titles which can happen with multiple languages
    titles_hash = titles.pluck(:rdf_uri, :cache, "sources.language", :url)
                        .map { |title| [title[0], title[1]] unless title[1].blank? }
                        .to_h

    photos = get_event_photos time_span
    photos_hash = photos.pluck(:rdf_uri, :cache).to_h

    dates = get_event_dates time_span
    dates_hash = dates.pluck(:rdf_uri, :cache)
                      .map { |array| [array[0], helpers.parse_date_string_array(array[1])] }
                      .to_h

    archive_dates = get_archive_dates
    archive_dates_hash = archive_dates.to_h

    event_status = get_event_status
    uris_with_problems = event_status.select{|event| event[1] == "problem"}.map{|event| event = event[0]}
    uris_to_review = event_status.select{|event| event[1] == "initial"}.map{|event| event = event[0]}
    uris_updated = event_status.select{|event| event[1] == "updated"}.map{|event| event = event[0]}

    uris_title_publishable = titles.select { |s| (s.status == 'ok' || s.status == 'updated') }
                                   .map { |s| s.webpage.rdf_uri }
                                   .uniq
    uris_dates_publishable = dates.select { |s| (s.status == 'ok' || s.status == 'updated') }
                                  .map { |s| s.webpage.rdf_uri }
                                  .uniq
    uris_location_publishable = get_uris_publishable "Location"

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

  def get_event_titles archive_date_range = [Time.now - 10.years..Time.now + 10.years]
    Statement.joins({source: [:property, :website]},:webpage)
             .where({sources:{selected: true, properties:{label: "Title", rdfs_class: 1}, websites:  {seedurl: params[:seedurl]}, webpages: {archive_date: archive_date_range}  }  }  )
  end

  def get_event_photos archive_date_range = [Time.now - 10.years..Time.now + 10.years]
    Statement.joins({source: [:property, :website]},:webpage).where({sources:{selected: true, properties:{label: "Photo", rdfs_class: 1}, websites:  {seedurl:  params[:seedurl]}, webpages: {archive_date: archive_date_range}   }  }  )
             .order(:created_at)
  end

  def get_event_dates archive_date_range = [Time.now - 10.years..Time.now + 10.years]
    Statement.joins({source: [:property, :website]},:webpage).where({sources:{selected: true, properties:{label: "Dates", rdfs_class: 1}, websites:  {seedurl:  params[:seedurl]}, webpages: {archive_date: archive_date_range}   }  }  ).order(:created_at)
  end

  def get_archive_dates
    Webpage.joins(:website).where(rdfs_class: 1, websites: {seedurl: params[:seedurl]}).order(:archive_date).pluck(:rdf_uri, :archive_date)
  end

  def get_event_status
    Statement.joins({webpage: :website},:source).where(webpages:{websites: {seedurl: params[:seedurl]}}).where(sources: {selected: true}).pluck(:rdf_uri, :status).uniq
  end

  def get_uris_publishable(property)
    # get property across all events in the website
    # TODO: This is misleading for bilingual sites which will have a publishable title 
    # if either en or fr meets the conditions of ok || updated
    publishable_uris = Statement.joins({ source: [:property, :website] }, :webpage)
                                .where(webpages: { websites: { seedurl: params[:seedurl] } })
                                .where(sources: { selected: true })
                                .where(sources: { properties: { label: property, rdfs_class: 1 } })
    # keep only those with status  OK || updated
    publishable_uris.select { |s| (s.status == 'ok' || s.status == 'updated') }
                           .map { |s| s.webpage.rdf_uri }
                           .uniq
  end
end
