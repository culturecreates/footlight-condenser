class StatementsController < ApplicationController
  include HarmonizedIndexParams

  before_action :set_statement, only: [:refresh, :show, :edit, :update, :destroy, :add_linked_data, :remove_linked_data, :activate]
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate, only: [:show, :index]
  helper_method :expand_trace_for_view, :trace_steps_for_view, :trace_presenter

  MANUALLY_ADDED = "Manually added"
  TRACE_CODE_DEFAULT = 140
  TRACE_OUTPUT_DEFAULT = 140
  TRACE_ERROR_DEFAULT = 160

  # GET /statements/webpage.json?url=http://
  def webpage
    @statements = []
    webpage = Webpage.where(url: params[:url]).first
    webpage.statements.each do |statement|
      @statements << statement
    end
    @statements.sort
  end

  # PATCH /statements/refresh_webpage.json?url=http://
  def refresh_webpage
    webpage = Webpage.includes(:website).where(url: params[:url]).first
    return render_missing_refresh_webpage if webpage.blank?

    error_list = refresh_webpage_statements(webpage,  webpage.website.default_language)
    respond_to do |format|
        format.html { redirect_to webpage_statements_path(url: params[:url]), notice: refresh_summary_notice(success_message: "Webpage statements refreshed.", errors: error_list, error_prefix: "Refresh completed") }
        format.json { render json: { message: refresh_summary_notice(success_message: "Webpage statements refreshed.", errors: error_list, error_prefix: "Refresh completed"), errors: compact_refresh_error_list(error_list) }.to_json }
    end
  end

  # PATCH /statements/refresh_rdf_uri.json?rdf_uri=
  # PATCH /statements/refresh_rdf_uri.json?rdf_uri=&force_scrape_every_hrs=24
  def refresh_rdf_uri
    error_list = []
    webpages = Webpage.includes(:website).where(rdf_uri: params[:rdf_uri])
    return render_missing_refresh_rdf_uri if webpages.blank?

    webpages.each do |webpage|
      errors = refresh_webpage_statements(webpage, webpage.website.default_language, refresh_rdf_uri_scrape_options)
      error_list << {"Webpage id: #{webpage.id}" => errors}
    end
    respond_to do |format|
      format.html { redirect_to statements_path(rdf_uri: params[:rdf_uri]), notice: refresh_summary_notice(success_message: "URI refreshed.", errors: error_list, item_label: "webpage errors", error_prefix: "URI refreshed") }
      format.json { render json: { message: refresh_summary_notice(success_message: "URI refreshed.", errors: error_list, item_label: "webpage errors", error_prefix: "URI refreshed"), errors: compact_refresh_error_list(error_list) }.to_json }
    end
  end


  # PATCH /statements/1/refresh
  # PATCH /statements/1/refresh.json
  def refresh
    result = statement_refresh_helper_proxy.refresh_statement_helper(@statement)
    trace_enabled = cookies[:dsl_trace] == "true"
    data = result[:data]
    abort_payload = extract_abort_payload(data)

    if trace_enabled
      if Rails.env.development? || ENV["DSL_TRACE_DEBUG"]
        Rails.logger.debug do
          "[DSL TRACE FULL]\n#{JSON.pretty_generate(result[:trace] || [])}"
        end
      end

      trace_for_session = Dsl::Tracing::TraceFormatter.for_session_v2(result[:trace] || [])

      session[:dsl_trace] = trace_for_session
      Rails.logger.debug { "[DSL TRACE SESSION SIZE] #{JSON.generate(session[:dsl_trace]).bytesize}" }
    else
      session.delete(:dsl_trace)
    end

    respond_to do |format|
      if abort_payload.present?
        compact_error = helpers.compact_refresh_error(abort_payload)
        error_type = abort_payload[:error_type].presence || "DslAbort"
        error_message = abort_payload[:error].presence || "DSL runner aborted"

        format.html do
          flash[:alert] = "Statement Error: #{compact_error}"
          redirect_to @statement
        end
        format.json do
          render json: {
            status: "error",
            kind: "dsl_abort",
            error: error_message,
            error_type: error_type,
            step: abort_payload[:step],
            source: abort_payload[:source]
          }, status: :unprocessable_entity
        end
      elsif result[:errors].present?
        format.html do
          flash[:alert] = "Statement Error: " + Array(result[:errors]).join(". ")
          redirect_to @statement
        end
        format.json do
          render json: {
            status: "error",
            kind: "refresh_error",
            error: Array(result[:errors]).join(". "),
            error_type: "RefreshError",
            step: nil,
            source: "statements_controller"
          }, status: :unprocessable_entity
        end
      else
        format.html do
          flash[:notice] = "Statement was successfully refreshed."
          redirect_to @statement
        end
        format.json do
          render json: {
            status: "ok",
            statement_id: @statement.id,
            result_present: data.present?,
            trace_present: result[:trace].present?
          }
        end
      end
    end
  end


  # GET /statements?rdf_uri=&seedurl=&prop=&status=
  # GET /statements.json
  def index
    index_params = harmonized_index_params(
      allowed_filters: Statements::IndexQuery::FILTER_KEYS,
      allowed_sorts: Statements::IndexQuery::SORT_COLUMNS.keys,
      default_sort: Statements::IndexQuery::DEFAULT_SORT,
      default_direction: Statements::IndexQuery::DEFAULT_DIRECTION,
      default_per_page: Statements::IndexQuery::DEFAULT_PER_PAGE,
      max_per_page: Statements::IndexQuery::MAX_PER_PAGE
    )

    canonical = harmonized_index_canonical_params(
      index_params,
      default_sort: Statements::IndexQuery::DEFAULT_SORT,
      default_direction: Statements::IndexQuery::DEFAULT_DIRECTION,
      default_per_page: Statements::IndexQuery::DEFAULT_PER_PAGE
    )
    raw = harmonized_index_raw_params(allowed_filters: Statements::IndexQuery::FILTER_KEYS, preserve: %w[sort direction page per_page])
    return redirect_to(statements_path(canonical)) if request.format.html? && canonical != raw

    @filters = index_params[:filters]
    @sort = index_params[:sort]
    @direction = index_params[:direction]
    @pagination = { page: index_params[:page], per_page: index_params[:per_page] }
    @sortable_filters = @filters.merge(per_page: @pagination[:per_page])
    @statement_table_headers = HarmonizedTableHeaders.statements(
      show_seedurl_col: @filters[:seedurl].blank? || @filters[:seedurl] == "all"
    )
    @statements = Statements::IndexQuery.call(
      filters: @filters,
      sort: @sort,
      direction: @direction,
      page: @pagination[:page],
      per_page: @pagination[:per_page]
    )
  end

  # GET /statements/1
  # GET /statements/1.json
  def show
    trace = session[:dsl_trace]
    trace = trace.to_h if trace.respond_to?(:to_h)
    trace = nil if trace == {}
    @trace = safe_trace_copy(trace)
    @trace ||= []
    @trace_presenter = TracePresenter.new(@trace)
    @trace_view_mode = @trace_presenter.mode(cookies)
    code_len = (cookies[:trace_code_display_length].presence || TRACE_CODE_DEFAULT).to_i
    output_len = (cookies[:trace_output_display_length].presence || TRACE_OUTPUT_DEFAULT).to_i
    error_len = (cookies[:trace_error_display_length].presence || TRACE_ERROR_DEFAULT).to_i

    @trace_code_length = code_len.positive? ? code_len : TRACE_CODE_DEFAULT
    @trace_output_length = output_len.positive? ? output_len : TRACE_OUTPUT_DEFAULT
    @trace_error_length = error_len.positive? ? error_len : TRACE_ERROR_DEFAULT

    @show_trace = @trace_presenter.visible?(cookies)
    @result = nil
  end

  attr_reader :trace_presenter

  def expand_trace_for_view(compact_trace)
    return [] if compact_trace.nil?
    return compact_trace if compact_trace.is_a?(Array)

    raw = compact_trace.respond_to?(:to_h) ? compact_trace.to_h : compact_trace
    return [] unless raw.is_a?(Hash)

    payload = raw.with_indifferent_access
    return expand_trace_v2_for_view(payload) if payload[:version].to_i == 2

    expand_trace_v1_for_view(payload)
  end

  def trace_steps_for_view(trace)
    interpreter = Dsl::SemanticInterpreter.new
    steps = expand_trace_for_view(trace).map { |step| normalize_trace_semantics(step) }
    interpreter.annotate(steps)
  end

  def expand_trace_v1_for_view(payload)
    urls = Array(payload[:urls]).map(&:to_s)

    Array(payload[:events]).map do |event|
      source = event.respond_to?(:to_h) ? event.to_h : event
      e = source.is_a?(Hash) ? source.with_indifferent_access : {}

      {
        step: e[:s],
        type: e[:t],
        code: e[:c],
        input: e[:i],
        output: e[:o],
        probe: expand_compact_probe(e[:p]),
        wringer: expand_compact_wringer(e[:w]),
        url_before: resolve_trace_url(urls, e[:ub]),
        url_after: resolve_trace_url(urls, e[:ua]),
        duration_ms: e[:d],
        error: e[:e]
      }
    end
  end

  def expand_trace_v2_for_view(payload)
    urls = Array(payload[:urls]).map(&:to_s)
    initial = (payload[:initial] || {}).with_indifferent_access

    current_state = initial[:state]
    current_url = initial[:url]

    Array(payload[:steps]).map do |step|
      source = step.respond_to?(:to_h) ? step.to_h : step
      s = source.is_a?(Hash) ? source.with_indifferent_access : {}

      output = s[:of] || s[:o]
      next_url = s.key?(:ua) ? resolve_trace_url(urls, s[:ua]) : current_url
      input = current_state
      output = input if output.nil?
      expanded = {
        step: s[:s],
        type: s[:t],
        code: s[:cf] || s[:c],
        input: input,
        output: output,
        probe: expand_compact_probe(s[:p]),
        wringer: expand_compact_wringer(s[:w]),
        url_before: current_url,
        url_after: next_url,
        duration_ms: s[:d],
        error: s[:e]
      }

      current_state = output
      current_url = next_url

      expanded
    end
  end


  # GET /statements/search_name.json?str=expected_class=
  def search_name
    webpage = Webpage.find_by(id: params[:webpage_id])

    uris = helpers.search_everywhere(
      params["str"],
      params["expected_class"],
      webpage
    )

    render json: uris
  end

  # GET /statements/new
  def new
    @statement = Statement.new
    @websites = Website.all
  end

  # GET /statements/1/edit
  def edit
    @websites = Website.all
  end

  # POST /statements
  # POST /statements.json
  def create
    @statement = Statement.new(statement_params)
    respond_to do |format|
      if @statement.save
        format.html { redirect_to @statement, notice: 'Statement was successfully created.' }
        format.json { render :show, status: :created, location: @statement }
      else
        format.html { render :new }
        format.json { render json: @statement.errors, status: :unprocessable_entity }
      end
    end
  end
  

  # PATCH/PUT /statements/1
  # PATCH/PUT /statements/1.json
  def update
    respond_to do |format|
      if @statement.update(statement_params)
        if statement_params.include?("cache") && !statement_params.include?("manual")
          # This statement's value has been edited so it should be set to manual so it does not get updated automatically
          @statement.update(manual: true)
        end
        format.html { redirect_to statements_path(rdf_uri: @statement.webpage.rdf_uri), notice: 'Statement was successfully updated.' }
        format.json { redirect_to uri_resources_path(uri: @statement.webpage.rdf_uri, format: :json)}
      else
        format.html { render :edit }
        format.json { render json: @statement.errors, status: :unprocessable_entity }
      end
    end
  end

  # POST /statements/batch_update?data=
  # For INTERNAL use of Condenser admin webpages
  def batch_update 
    if params[:commit] == "View"
      redirect_to statements_path(batch_redirect_params)
    end
    if params[:commit] == "Update"
      @statements = build_query
      update_data = eval(params[:update_data])
      @statements.each do |stat|
        if !stat.update(update_data)
          return redirect_to statements_path(batch_redirect_params), notice: 'Failed to update.'
        end
      end
      redirect_to statements_path(batch_redirect_params)
    end
    if params[:commit] == "Refresh all listed"
      statements = build_query
      error_list = []
      statements.each do |stat|
        result = helpers.refresh_statement_helper(stat)
        compact_errors = Array(result[:errors]).presence || stat.errors.full_messages
        error_list << "Statement id #{stat.id}: #{compact_errors.first}" if compact_errors.present?
      end
      notice =
        if error_list.any?
          "Refresh completed with #{error_list.size} errors. First: #{error_list.first}"
        else
          "Statements refreshed."
        end
      redirect_to statements_path(batch_redirect_params), notice: notice
    end
    if params[:commit] == "Review all listed" 
      statements = build_query
      status_origin = "condenser-admin-review-all"
      statements.each do |statement|
        next if statement.is_problem? || statement.status == 'ok'

        statement.status = 'ok'
        statement.status_origin = status_origin
        statement.save
      end
      redirect_to statements_path(batch_redirect_params), notice: 'Statements successfully reviewed.'
    end

  end


  # PATCH/PUT /statements/1/add_linked_data.json
  # Structure of statement_params { "statement": {"cache": "[\"#{options[:name]}\",\"#{options[:rdfs_class]}\",\"#{options[:uri]}\"]", "status": "ok", "status_origin": user_name} }
  def add_linked_data
    s = statement_params
    statement_cache = if @statement.cache.blank?
                        [] 
                      else
                        JSON.parse(@statement.cache) 
                      end
    if statement_cache[0].class != Array
      statement_cache = [statement_cache]
    end
    link_added = false
    statement_cache.each_with_index do |c,i|
      if c[0] == MANUALLY_ADDED 
        statement_cache[i] << [JSON.parse(s['cache'])[0], JSON.parse(s['cache'])[2]]
        link_added = true
      end
    end
    if !link_added 
      statement_cache << [MANUALLY_ADDED,JSON.parse(s['cache'])[1], [JSON.parse(s['cache'])[0], JSON.parse(s['cache'])[2]]]
    end
    s['cache'] = statement_cache.to_s
    respond_to do |format|
      if @statement.update(s)
        format.html { redirect_to show_resources_path(rdf_uri: @statement.webpage.rdf_uri), notice: 'Statement was successfully updated.' }
        format.json { redirect_to uri_resources_path(uri: @statement.webpage.rdf_uri, format: :json)}
      else
        format.html { render :edit }
        format.json { render json: @statement.errors, status: :unprocessable_entity }
      end
    end
  end


  # PATCH/PUT /statements/1/remove_linked_data.json
  # Structure of statement_params: { "statement": {"cache": "[\"#{options[:name]}\",\"#{options[:rdfs_class]}\",\"#{options[:uri]}\"]", "status": "ok", "status_origin": user_name} }
  def remove_linked_data
    s = statement_params
    statement_cache = JSON.parse(@statement.cache)
    label_to_delete = JSON.parse(s['cache'])[0]
    class_to_delete = JSON.parse(s['cache'])[1]
    uri_to_delete =  JSON.parse(s['cache'])[2]
    statement_cache = helpers.process_linked_data_removal(statement_cache, uri_to_delete, class_to_delete, label_to_delete)
    s['cache'] = statement_cache.to_s
    respond_to do |format|
      if @statement.update(s)
        format.html { redirect_to show_resources_path(rdf_uri: @statement.webpage.rdf_uri), notice: 'Statement was successfully updated.' }
        format.json { redirect_to show_resources_path(rdf_uri: @statement.webpage.rdf_uri, format: :json)}
      else
        format.html { render :edit }
        format.json { render json: @statement.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /statements/1/activate
  # PATCH/PUT /statements/1/activate.json
  # Sets the source of this statement to selected = true, and sets the other sources of the same property/lanague to false.
  # Also switchs selected individual for all events of this website.
  def activate
    helpers.activate_source(@statement)
    rdf_uri = @statement.webpage.rdf_uri
    respond_to do |format|
        format.html { redirect_to statements_path(rdf_uri: rdf_uri), notice: 'Statement was successfully activated.' }
        format.json { redirect_to show_resources_path(rdf_uri: rdf_uri, format: :json)}
    end
  end

  # PATCH/PUT /statements/1/activate_individual
  # PATCH/PUT /statements/1/activate_individual.json
  def activate_individual
    #get all statements about this property/language for the resource(individual)
    @statement = Statement.find(params[:id])
    @property = @statement.source.property
    @webpage =  @statement.webpage
    # Get list of statements that share the same source property id and source 
    @statements = Statement.includes({source: [:property]}, :webpage).where(sources: {property: @property}, webpage_id: @webpage)
    #set all statement.selected_individual = false
    @statements.each do |statement|
      if statement != @statement
        if statement.source.selected
          # toggle selected individual and also review selected so we can check for update state on selected source (a date change should be alterted to the user)
          statement.update(selected_individual: false, status: 'ok')
        else
          statement.update(selected_individual: false)
        end 
      else
        statement.update(selected_individual: true)
      end
    end
    respond_to do |format|
        format.html { redirect_to statements_path(rdf_uri: @webpage.rdf_uri), notice: 'Statement was successfully activated.' }
        format.json { redirect_to show_resources_path(rdf_uri: @webpage.rdf_uri, format: :json)}
    end
  end

  # PATCH/PUT /statements/1/deactivate_individual
  # PATCH/PUT /statements/1/deactivate_individual.json
  # Set all this entity's statements of property/language back to source template
  def deactivate_individual
    @statement = Statement.find(params[:id])
    @property = @statement.source.property
    @webpage =  @statement.webpage
 
    # Get list of statements that share the same source property id and source 
    @statements = Statement.includes({source: [:property]}, :webpage).where(sources: {property: @property}, webpage_id: @webpage)
    @statements.each do |statement|
      if statement.source.selected
        statement.update(selected_individual: true)
      else
        statement.update(selected_individual: false)
      end
    end
    respond_to do |format|
        format.html { redirect_to statements_path(rdf_uri: @statement.webpage.rdf_uri), notice: 'Statement was successfully deactivated.' }
        format.json { redirect_to show_resources_path(rdf_uri: @statement.webpage.rdf_uri, format: :json)}
    end
  end

  # DELETE /statements/1
  # DELETE /statements/1.json
  def destroy
    @statement.destroy
    respond_to do |format|
      format.html { redirect_to statements_url, notice: 'Statement was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  ##
  # Refresh all modelled statements for a webpage. Create new ones if needed.
  # INPUT
  #   webpage = ActiveRecord webpage
  #   default_language = default lanuguage of website: en | fr | nil
  #   scrape_options = {} to pass to Footlight-wringer scrapping service
  #
  def refresh_webpage_statements(webpage, default_language = "en", scrape_options={})
    Statements::RefreshWebpageStatementsService.new(
      refresh_helper: statement_refresh_helper_proxy
    ).call(
      webpage: webpage,
      default_language: default_language,
      scrape_options: normalized_scrape_options(scrape_options)
    )
  end


  private

  def statement_refresh_helper_proxy
    StatementsHelper.build_refresh_proxy(cookies: request_cookie_snapshot)
  end

  def request_cookie_snapshot
    return {} unless request.respond_to?(:cookies)

    source = request.cookies || {}

    source.with_indifferent_access
  rescue StandardError
    {}
  end

  def safe_trace_copy(obj)
    case obj
    when Array
      obj.map { |e| safe_trace_copy(e) }
    when Hash
      obj.transform_values do |v|
        safe_trace_copy(v)
      end
    else
      obj
    end
  end

  # Must stay in sync with DSL runner abort contract:
  # ["abort_update", payload]
  def abort_structure?(obj)
    obj.is_a?(Array) && obj.first == "abort_update"
  end

  def extract_abort_payload(data)
    return nil unless abort_structure?(data)

    payload = data.second
    payload = payload.to_h if payload.respond_to?(:to_h)

    unless payload.is_a?(Hash)
      payload = {
        error: "Malformed abort payload",
        error_type: "InvalidAbortPayload",
        source: "statements_controller"
      }
    end

    payload = payload.with_indifferent_access if payload.respond_to?(:with_indifferent_access)
    payload
  end

  def refresh_rdf_uri_scrape_options
    { force_scrape_every_hrs: params[:force_scrape_every_hrs] }
  end

  def render_missing_refresh_webpage
    message = "Webpage not found for URL: #{params[:url]}"

    respond_to do |format|
      format.html { redirect_to webpage_statements_path(url: params[:url]), alert: message }
      format.json { render json: { error: message, url: params[:url] }, status: :not_found }
    end
  end

  def render_missing_refresh_rdf_uri
    message = "No webpages found for RDF URI: #{params[:rdf_uri]}"

    respond_to do |format|
      format.html { redirect_to statements_path(rdf_uri: params[:rdf_uri]), alert: message }
      format.json { render json: { error: message, rdf_uri: params[:rdf_uri] }, status: :not_found }
    end
  end

  def normalized_scrape_options(scrape_options)
    return {} unless scrape_options.respond_to?(:to_h)

    scrape_options.to_h.symbolize_keys
  end

  def refresh_summary_notice(success_message:, errors:, item_label: "errors", error_prefix: nil)
    compact_errors = compact_refresh_error_list(errors)
    return success_message if compact_errors.empty?

    prefix = error_prefix.presence || success_message.delete_suffix(".")
    "#{prefix} with #{compact_errors.size} #{item_label}. First: #{compact_errors.first}"
  end

  def compact_refresh_error_list(errors)
    Array(errors).flat_map { |entry| compact_refresh_entries(entry) }.reject(&:blank?)
  end

  def compact_refresh_entries(entry, prefix = nil)
    case entry
    when String
      [prefix.present? ? "#{prefix}: #{entry}" : entry]
    when Hash
      if entry.key?(:error) || entry.key?("error") || entry.key?(:error_type) || entry.key?("error_type")
        message = helpers.compact_refresh_error(entry)
        [prefix.present? ? "#{prefix}: #{message}" : message]
      else
      entry.flat_map do |key, value|
        compact_refresh_entries(value, [prefix, key].compact.join(": "))
      end
      end
    when Array
      if entry.size == 2 && (entry.first.is_a?(String) || entry.first.is_a?(Symbol))
        compact_refresh_entries(entry.last, [prefix, entry.first].compact.join(": "))
      else
        entry.flat_map { |nested| compact_refresh_entries(nested, prefix) }
      end
    else
      message = helpers.compact_refresh_error(entry)
      [prefix.present? ? "#{prefix}: #{message}" : message]
    end
  end

  def resolve_trace_url(urls, index)
    return nil if index.nil?

    urls[index.to_i]
  rescue StandardError
    nil
  end

  def expand_compact_probe(payload)
    raw = payload.respond_to?(:to_h) ? payload.to_h : payload
    return { skipped: true } unless raw.is_a?(Hash)

    p = raw.with_indifferent_access
    return { skipped: true } if p[:sk]
    return { skipped: true } if p[:x].blank?

    output = Array(p[:o]).compact.map(&:to_s).first(3)
    status = p[:st].presence || "ok"

    {
      result: {
        status: status,
        xpath: p[:x],
        output: output
      },
      ok: p.key?(:ok) ? p[:ok] : (status == "ok")
    }
  rescue StandardError
    { skipped: true }
  end

  def expand_compact_wringer(payload)
    raw = payload.respond_to?(:to_h) ? payload.to_h : payload
    return { inherited: true } unless raw.is_a?(Hash)

    w = raw.with_indifferent_access
    return { inherited: true } if w[:i]

    {
      error_type: w[:et],
      retry: w[:r],
      cache: w[:c],
      unreachable: w[:u],
      received_404: w[:r404],
      system_error: w[:se],
      policy_action: w[:pa],
      signals: w[:s],
      hints: w[:h]
    }.compact
  rescue StandardError
    { inherited: true }
  end

  def normalize_trace_semantics(step)
    raw = step.respond_to?(:to_h) ? step.to_h : {}
    s = raw.is_a?(Hash) ? raw.with_indifferent_access : {}.with_indifferent_access

    normalized_probe =
      if s[:probe].is_a?(Hash)
        probe = s[:probe].with_indifferent_access
        if probe[:skipped]
          { skipped: true }
        elsif probe[:result].is_a?(Hash)
          { result: probe[:result], ok: probe[:ok] }
        elsif probe[:xpath].present?
          {
            result: {
              status: probe[:status],
              xpath: probe[:xpath],
              output: probe[:output]
            }.compact,
            ok: probe[:status].to_s == "ok"
          }
        else
          { skipped: true }
        end
      else
        { skipped: true }
      end

    normalized_wringer =
      if s[:wringer].is_a?(Hash)
        wringer = s[:wringer].with_indifferent_access
        (wringer.presence || { inherited: true })
      else
        { inherited: true }
      end

    s.merge(
      probe: normalized_probe,
      wringer: normalized_wringer
    )
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_statement
    @statement = Statement.find_by(id: params[:id])

    return if @statement

    respond_to do |format|
      format.html do
        redirect_to statements_path, alert: "Statement not found"
      end
      format.json do
        render json: {
          error: "Statement not found",
          id: params[:id]
        }, status: :not_found
      end
    end
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def statement_params
    params.require(:statement).permit(:manual, :cache, :status, :status_origin, :cache_refreshed, :cache_changed, :source_id, :webpage_id, :selected_individual)
  end

  def extract_property_ids rdfs_class_name, property_ids
    # recursive function to traverse tree of properties and add properties of sub-classes
    # with data type of Blank Node or "bnode"
    class_list = rdfs_class_name.split(',')
    class_list.each do |c|
      rdfs_class = RdfsClass.where(name: c).first
      if rdfs_class
        rdfs_class.properties.each do |property|
          property_ids << property.id
         ### TODO: is skipping xsd:uri ok? if ((property.value_datatype == "bnode" || property.value_datatype == "xsd:anyURI") && property.expected_class != rdfs_class_name)
          if (property.value_datatype == "bnode"  && property.expected_class != rdfs_class_name)
            extract_property_ids property.expected_class, property_ids
          end
        end
      end
    end
    return property_ids
  end

  def build_query
    Statements::IndexQuery.call(
      filters: harmonized_index_filters(allowed: Statements::IndexQuery::FILTER_KEYS),
      sort: params[:sort],
      direction: params[:direction],
      page: params[:page],
      per_page: params[:per_page].presence || Statements::IndexQuery::DEFAULT_PER_PAGE,
      paginate: true
    )
  end

  def batch_redirect_params
    harmonized_index_filters(allowed: Statements::IndexQuery::FILTER_KEYS)
      .merge(
        sort: params[:sort].presence,
        direction: params[:direction].presence,
        page: params[:page].presence,
        per_page: params[:per_page].presence
      )
      .compact
  end

end
