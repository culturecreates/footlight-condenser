
class EventsController < ApplicationController
  include HarmonizedIndexParams
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
    property_id = params[:property].to_i
    @property_ids = [Property.find_by(label: "Title")&.id].compact
    @property_ids << property_id if property_id.positive?
    @property_labels = @property_ids.map do |id|
      Property.find_by(id: id)&.label
    end.compact
  
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
    index_params = harmonized_index_params(
      allowed_filters: Events::IndexQuery::FILTER_KEYS,
      allowed_sorts: Events::IndexQuery::SORT_COLUMNS,
      default_sort: Events::IndexQuery::DEFAULT_SORT,
      default_direction: Events::IndexQuery::DEFAULT_DIRECTION,
      default_per_page: Events::IndexQuery::DEFAULT_PER_PAGE,
      max_per_page: Events::IndexQuery::MAX_PER_PAGE
    )
    index_params[:filters] = index_params[:filters].merge(seedurl: params[:seedurl])

    canonical = harmonized_index_canonical_params(
      index_params,
      default_sort: Events::IndexQuery::DEFAULT_SORT,
      default_direction: Events::IndexQuery::DEFAULT_DIRECTION,
      default_per_page: Events::IndexQuery::DEFAULT_PER_PAGE,
      preserve: {},
      exclude_filters: [:seedurl]
    )
    raw = harmonized_index_raw_params(allowed_filters: Events::IndexQuery::FILTER_KEYS - [:seedurl], preserve: %w[sort direction page per_page])
    return redirect_to(website_events_path(canonical)) if request.format.html? && canonical != raw

    @filters = index_params[:filters]
    @sort = index_params[:sort]
    @direction = index_params[:direction]
    @pagination = { page: index_params[:page], per_page: index_params[:per_page] }
    @sortable_filters = @filters.except(:seedurl).merge(per_page: @pagination[:per_page])
    @event_table_headers = HarmonizedTableHeaders.events
    @events = Events::IndexQuery.call(
      filters: @filters,
      sort: @sort,
      direction: @direction,
      page: @pagination[:page],
      per_page: @pagination[:per_page]
    )
    @total_events = @events.count
  end

  # Return a hash of event uris with grouped statements per event.
  def website_statements_by_event(seedurl, archive_date_range = [Time.zone.now - 3000.years..Time.zone.now + 3000.years])
    website_statements =
      Statement
      .joins(:webpage, source: :website)
      .includes({ source: [:property, :website] }, :webpage)
      .where(
        websites: { seedurl: seedurl },
        webpages: { archive_date: archive_date_range, rdfs_class_id: RdfsClass.where(name: "Event") }
      )
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
      Time.zone.now
    end
    end_date =  if valid_date?(end_date_input)
      Date.parse(end_date_input)
    else
      Time.zone.now + 5.years
    end 
    return [start_date..end_date]
  end

  def require_seedurl!
    return if params[:seedurl].present?

    respond_to do |format|
      format.json { render json: { error: "Missing seedurl" }, status: :bad_request }
      format.html do
        redirect_back fallback_location: websites_path,
                      alert: "Missing seedurl in URL (expected /websites/:seedurl/events_by_property)"
      end
    end
  end

  # GET /events/:id/pipeline_health.json
  def pipeline_health
    evaluation = Dsl::PipelineEvaluator.evaluate(event: params[:id])
    diagnosis = evaluation[:diagnosis] || {}

    render json: {
      event_id: params[:id],
      pipeline: {
        status: diagnosis[:status],
        category: diagnosis[:category],
        message: diagnosis[:message],
        suggested_action: diagnosis[:suggested_action],
        metrics: evaluation[:metrics] || {},
        details: diagnosis[:details] || {}
      }
    }
  end
  
end
