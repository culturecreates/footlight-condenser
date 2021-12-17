# Main API call for portal to get the index of events
# GET /websites/:seedurl/events?startDate=&endDate=
class EventsController < ApplicationController
  include ResourcesHelper # for get_uris method
   
  # GET /websites/:seedurl/events_by_property.json
  # GET statements for a specific property and handle selected_individuals.
  # Use in Concolse when viewing by property
  # Inputs: 
  #     params[:startDate] # "2018-01-01"
  #     params[:endDate] # "2021-01-01"
  #     params[:seedurl] 
  #     params[:property] # Title
  # Outputs: @time_span, @events, @seedurl, @property_ids
  def index_by_property
    @seedurl = params[:seedurl]
    start_date =  if valid_date?(params[:startDate])
                    Date.parse(params[:startDate])
                  else
                    Time.now
                  end
    end_date =  if valid_date?(params[:endDate])
                  Date.parse(params[:endDate])
                else
                  Time.now.next_year + 6.months
                end 
    @time_span = [start_date..end_date]

    @property_ids = [Property.where(label: "Title").first.id] << params[:property].to_i
    
    @property_labels = [] 
    @property_ids.each do |prop_id|
      @property_labels << Property.find(prop_id).label
    end
    
    # Psudocode

    # 1. Get all statements of webpages with class Event and website seedurl and with archive data within date range
    website_statements =
      Statement
      .includes({ source: [:property, :website] }, :webpage)
      .where({ sources:  { properties: { id: @property_ids }, websites: { seedurl: @seedurl }, webpages: { archive_date: @time_span } } })
      .order(:webpage_id)
      .order(selected_individual: :desc)

    # 2. For statements grouped by webpage, set subject and for each statement with same subject (uri), call build_nested_statement 
    current_page = nil
    override = []
    all_webpage_statements = {}
    webpage_statements = {}
    subject = nil
    website_statements.each do |stat|
      if current_page == stat.webpage_id 
        statements, override = build_nested_statement(webpage_statements, stat, override: override,subject: subject, webpage_class_name: "Event")
        all_webpage_statements[subject].merge!(statements)
      else
        current_page = stat.webpage_id
        override = []
        subject = stat.webpage.rdf_uri
        webpage_statements = {}
        statements, override = build_nested_statement(webpage_statements, stat, override: override,subject: subject, webpage_class_name: "Event")
        all_webpage_statements[subject] = {} if all_webpage_statements[subject].nil?
        all_webpage_statements[subject].merge!(statements) # to include en and fr webpages together
        all_webpage_statements[subject].merge!({:archive_date =>  { :archive_date => stat.webpage.archive_date}})
      end
    end
    @events = all_webpage_statements
  end

  # GET /websites/:seedurl/events.json
  #     params[:startDate] # "2018-01-01"
  #     params[:endDate] # "2021-01-01"
  #     params[:seedurl]
  def index
    seedurl = params[:seedurl]
    start_date =  if valid_date?(params[:startDate])
                    Date.parse(params[:startDate])
                  else
                    Time.now
                  end
    end_date =  if valid_date?(params[:endDate])
                  Date.parse(params[:endDate])
                else
                  Time.now.next_year + 6.months
                end 
    time_span = [start_date..end_date]
    @events = []

    website_statements_by_event(seedurl, time_span).each do |k,v|
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
      .where({ sources: { websites: { seedurl: seedurl }, webpages: { archive_date: archive_date_range, rdfs_class_id: RdfsClass.where(name:'Event')  } } })
      .order(:selected_individual) # to display selected source
    
    # Group by event URI
    events_by_uri = Hash.new { |h,k| h[k] = {} }
    website_statements.each do |s|
      next unless s.selected_individual || s.source.selected 

      events_by_uri[s.webpage.rdf_uri] =
        events_by_uri[s.webpage.rdf_uri]
        .merge({ s.source.property.label => { cache: s.cache, status: s.status, selected_individual: s.selected_individual} })
        .merge({ archive_date: { cache: s.webpage.archive_date } })
    end
    events_by_uri
  end

  def event_publishable? data  
   # return false if data.has_key?("URI List")

    publishable_states = ['ok','updated']
    return false unless publishable_states.include?(data.dig('Dates',:status))
    return false unless publishable_states.include?(data.dig('Location',:status)) ||
                        publishable_states.include?(data.dig('Virtual Location',:status))
    return false unless publishable_states.include?(data.dig('Title',:status))

    true
  end

  def publishable_events(seedurl)
    all_events = website_statements_by_event(seedurl)

    publishable = []
    all_events.each do |e|
      publishable << e[0] if event_publishable?(e[1])
    end
    publishable
  end

  def valid_date?(str)
    return false if str.nil?
    begin
      Date.parse(str)
      return true
    rescue => e
      logger.error("Invalid Event date parameter: #{e.inspect}")
      return false
    end
  end
  
end
