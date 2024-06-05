
class EventsController < ApplicationController
  include ResourcesHelper
   
  ##
  # GET statements across a website for a property, or list of properties
  # Used in Console when viewing by property
  # GET /websites/:seedurl/events_by_property.json
  # Inputs: 
  #     params[:startDate] # "2018-01-01"
  #     params[:endDate] # "2021-01-01"
  #     params[:seedurl] 
  #     params[:property] # Title or Title,Duration
  # Outputs: @time_span, @events, @seedurl, @property_ids
  def index_by_property
    @seedurl = params[:seedurl]
    time_span = create_timespan(params[:startDate], params[:endDate])
    # Add title property for the first column in the table
    @property_ids = [Property.where(label: "Title").first.id] << params[:property].to_i
    @property_labels =  @property_ids.map { |id| Property.find(id).label }
  
    # Get statements matching critria
    website_statements =
      Statement
      .includes({ source: [:property, :website] }, :webpage)
      .where({ sources:  { properties: { id: @property_ids }, websites: { seedurl: @seedurl }, webpages: { archive_date: time_span } } })
      .order(:webpage_id)

    # For each statement, build_nested_statement and add to website events
    website_event_resources = Hash.new { |h,k| h[k] = {} }
    website_statements.each do |stat|
      subject = stat.webpage.rdf_uri
      statements = build_nested_statement(website_event_resources[subject], stat,subject: subject, webpage_class_name: "Event")
      website_event_resources[subject].merge!(statements) # to include en and fr webpages together
      website_event_resources[subject].merge!({:archive_date =>  { :archive_date => stat.webpage.archive_date}})
    end
    @events = website_event_resources
  end

  # Main API calls to get the index of events
  # GET /websites/:seedurl/events.json
  #     params[:startDate] # "2018-01-01"
  #     params[:endDate] # "2021-01-01"
  def index
    seedurl = params[:seedurl]
    time_span = create_timespan(params[:startDate], params[:endDate])
    
    @events = []

    website_statements_by_event(seedurl, time_span).each do |k,v|
      title = v.dig('title',:cache) || v.dig('title_fr',:cache) || v.dig('title_en',:cache)
      title = 'Error' if !title.present? || title.include?('error:')
      date =  helpers.parse_date_string_array(v.dig('dates', :cache)) || helpers.patch_invalid_date
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

  # Return a hash of event uris with grouped statements per event.
  def website_statements_by_event(seedurl, archive_date_range = [Time.now - 3000.years..Time.now + 3000.years])
    website_statements =
      Statement
      .includes({ source: [:property, :website] }, :webpage)
      .where({ sources: { websites: { seedurl: seedurl }, webpages: { archive_date: archive_date_range, rdfs_class_id: RdfsClass.where(name:'Event')  } } })
      .where(selected_individual: true)
    
    # Group by event URI
    events_by_uri = Hash.new { |h,k| h[k] = {} }
    website_statements.each do |s|
      property_label = make_key(s.source.property.label, s.source.language) 
      if events_by_uri[s.webpage.rdf_uri][property_label].present?
        logger.error "Error in Events by URI: #{s.webpage.rdf_uri} property #{property_label} has duplicate selected individuals"
        events_by_uri[s.webpage.rdf_uri].merge!({ property_label => { cache: s.cache, status: "problem", selected_individual: s.selected_individual} }) 
      else
        events_by_uri[s.webpage.rdf_uri]
          .merge!({ property_label => { cache: s.cache, status: s.status, selected_individual: s.selected_individual} })
          .merge!({ archive_date: { cache: s.webpage.archive_date } })
       end
    end
   
    events_by_uri
  end

  def make_key prop, lang
    begin
      _prop = prop.sub(" ", "_").downcase
      _lang = lang.downcase
      key = _prop
      if lang.present?
        key += "_#{_lang}"
      end
    rescue => exception
      key = "failed to make key"
    end
    return key
  end

  def event_publishable? data  
    # puts "data.dig('Dates',:status): #{data.dig('Dates',:status)}"
    publishable_states = ['ok','updated']
    return false unless publishable_states.include?(data.dig('dates',:status))
    return false unless publishable_states.include?(data.dig('location',:status)) ||
                        publishable_states.include?(data.dig('virtuallocation',:status))
    return false unless publishable_states.include?(data.dig('title_en',:status)) || 
                        publishable_states.include?(data.dig('title_fr',:status)) ||
                        publishable_states.include?(data.dig('title',:status))

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
    rescue 
      # logger.info("Invalid Event date}")
      return false
    end
  end

  def create_timespan(start_date_input, end_date_input)
    start_date =  if valid_date?(start_date_input)
      Date.parse(start_date_input)
    else
      Time.now
    end
    end_date =  if valid_date?(end_date_input)
      Date.parse(end_date_input)
    else
      Time.now + 5.years
    end 
    return [start_date..end_date]
  end
  
end
