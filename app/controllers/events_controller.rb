# Main API call for portal to get the index of events
# GET /websites/:seedurl/events?startDate=&endDate=
class EventsController < ApplicationController
  def index
    params[:startDate] # "2018-01-01"
    params[:endDate] # "2021-01-01"
    params[:seedurl]

    @events = []

    start_date = Time.now
    end_date = Time.now.next_year + 6.months

    if params[:startDate]
      begin
        start_date = Date.parse(params[:startDate])
      rescue => e
        logger.error("Invalid start_date parameter: #{e.inspect}")
      end
    end

    if params[:endDate]
      begin
        end_date = Date.parse(params[:endDate])
      rescue => e
        logger.error("Invalid end_date parameter: #{e.inspect}")
      end
    end

    time_span = [start_date..end_date]

    website_statements_by_event(params[:seedurl], time_span).each do |k,v|
      next if !v.has_key?('Title') # Exclude other classes that don't have Title, like Resource List Class

      title = if v.dig('Title',:cache).present? && !v.dig('Title', :cache).include?('error:')
                v.dig('Title',:cache)
              else
                'Error'
              end
      date =  helpers.parse_date_string_array(v.dig('Dates', :cache)) || helpers.patch_invalid_date
      @events << {
        rdf_uri: k,
        statements_status:
          {
            to_review: v.any? { |_a, b| b.flatten.include?('initial') },
            updated: v.any? { |_a,b| b.flatten.include?('updated') },
            problem: v.any? { |_a,b| b.flatten.include?('problem') },
            publishable: event_publishable?(v)
          },
        photo: v.dig('Photo',:cache),
        title: title,
        date: date,
        archive_date: v.dig(:archive_date,:cache)
      }
    end

    @events.sort_by! { |item| item[:archive_date] }
    @total_events = @events.count
  end

  def website_statements_by_event(seedurl, archive_date_range = [Time.now - 10.years..Time.now + 10.years])
    website_statements =
      Statement
      .includes({ source: [:property, :website] }, :webpage)
      .where({ sources: { selected: true, websites: { seedurl: seedurl }, webpages: { archive_date: archive_date_range } } })
      .order(:created_at)

    # Group by event URI
    events_by_uri = Hash.new { |h,k| h[k] = {} }
    website_statements.each do |s|
      events_by_uri[s.webpage.rdf_uri] =
        events_by_uri[s.webpage.rdf_uri]
        .merge({ s.source.property.label => { cache: s.cache, status: s.status } })
        .merge({ archive_date: { cache: s.webpage.archive_date } })
    end
    events_by_uri
  end

  def event_publishable? data  
    return false if data.has_key?("URI List")

    publishable_states = ['ok','updated']
    return false unless publishable_states.include?(data.dig('Dates',:status))
    return false unless publishable_states.include?(data.dig('Location',:status)) ||
                        publishable_states.include?(data.dig('Virtual Location',:status))
    return false unless publishable_states.include?(data.dig('Title',:status))

    true
  end
end
