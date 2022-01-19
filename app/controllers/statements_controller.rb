class StatementsController < ApplicationController
  before_action :set_statement, only: [:show, :edit, :update, :destroy, :add_linked_data, :remove_linked_data, :activate]
  skip_before_action :verify_authenticity_token

  MANUALLY_ADDED = "Manually added"

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
    refresh_webpage_statements(webpage,  webpage.website.default_language)
    respond_to do |format|
        format.html {redirect_to webpage_statements_path(url: params[:url]), notice: 'All statements were successfully refreshed.'}
        format.json {render json: {message:"statements refreshed"}.to_json }
    end
  end


  # PATCH /statements/refresh_rdf_uri.json?rdf_uri=
  # PATCH /statements/refresh_rdf_uri.json?rdf_uri=&force_scrape_every_hrs=24
  def refresh_rdf_uri
    params[:force_scrape_every_hrs] ||= nil
    webpages = Webpage.includes(:website).where(rdf_uri: params[:rdf_uri])
    webpages.each do |webpage|
      refresh_webpage_statements(webpage, webpage.website.default_language, :force_scrape_every_hrs => params[:force_scrape_every_hrs])
    end


    respond_to do |format|
      format.html { redirect_to statements_path(rdf_uri: params[:rdf_uri]), notice: 'Refresh requested on all statements. Check individual statements for success.' }
      format.json { render json: {message:"URI refreshed. Check individual statements for success."}.to_json }
    end
  end

  # PATCH /statements/1/refresh
  # PATCH /statements/1/refresh.json
  def refresh
   
    @statement = Statement.where(id: params[:id]).first
    prior_refresh = @statement.cache_refreshed
    refresh_statement @statement
    @statement = Statement.where(id: params[:id]).first
    post_refresh = @statement.cache_refreshed
    if prior_refresh == post_refresh && !@statement.source.algorithm_value.starts_with?("manual") && !@statement.manual
      @statement.errors[:base] << "Error scrapping. Refresh was aborted! Checks logs."
    end
    respond_to do |format|
      if @statement.errors.any?
        format.html { redirect_to @statement, notice: 'Statement errors' + @statement.errors.messages.inspect }
        format.json { render json: @statement.errors, status: :unprocessable_entity }
      else
        format.html { redirect_to @statement, notice: 'Statement was successfully refreshed.' }
        format.json { render :show, status: :refreshed, location: @statement }
      end
    end
  end


  # GET /statements?rdf_uri=&seedurl=&prop=&status=
  # GET /statements.json
  def index
    @statements = build_query(
      rdf_uri: params[:rdf_uri], 
      seedurl: params[:seedurl], 
      prop: params[:prop], 
      status: params[:status],
      selected: params[:selected],
      selected_individual: params[:selected_individual],
      source: params[:source]
    )

    # Paginate
    @statements = @statements.paginate(page: params[:page], per_page: params[:per_page])
  end

  # GET /statements/1
  # GET /statements/1.json
  def show
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


  # PATCH/PUT /statements/review_all
  def review_all 
    statements = build_query(rdf_uri: params[:rdf_uri], seedurl: params[:seedurl], prop: params[:prop], status: params[:status])
    status_origin = "condenser-admin-review-all"

    statements.each do |statement|
      next if statement.is_problem?

      statement.status = 'ok'
      statement.status_origin = status_origin
      statement.save
    end

    respond_to do |format|
      format.html { redirect_to statements_path(rdf_uri: params[:rdf_uri], seedurl:  params[:seedurl], prop:  params[:prop], status:  params[:status]), notice: 'Statements successfully reviewed.' }
      format.json { redirect_to statements_path(rdf_uri: params[:rdf_uri], seedurl:  params[:seedurl], prop:  params[:prop], status:  params[:status], format: :json) }
    end
  end

  # PATCH/PUT /statements/refresh_all
  def refresh_all 
    statements = build_query(rdf_uri: params[:rdf_uri], seedurl:  params[:seedurl], prop:  params[:prop], status:  params[:status])
    status_origin = "condenser-admin-refresh-all"

    statements.each do |statement|
      refresh_statement statement
    end

    respond_to do |format|
      format.html { redirect_to statements_path(rdf_uri: params[:rdf_uri], seedurl:  params[:seedurl], prop:  params[:prop], status:  params[:status]), notice: 'Statements refreshed.' }
      format.json { redirect_to statements_path(rdf_uri: params[:rdf_uri], seedurl:  params[:seedurl], prop:  params[:prop], status:  params[:status], format: :json) }
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
        format.json { redirect_to show_resources_path(rdf_uri: @statement.webpage.rdf_uri, format: :json)}
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
      redirect_to statements_path(request.parameters.except(:authenticity_token))
    end

    if params[:commit] == "Update"
      @statements = build_query(
        rdf_uri: params[:rdf_uri], 
        seedurl: params[:seedurl], 
        prop: params[:prop], 
        status: params[:status],
        selected: params[:selected],
        selected_individual: params[:selected_individual],
        source: params[:source]
      )
      update_data = eval(params[:update_data])
      @statements.each do |stat|
        if !stat.update(update_data)
          redirect_to statements_path(request.parameters.except(:authenticity_token), notice: 'Failed to update.')
        end
      end

      redirect_to statements_path(request.parameters.except(:authenticity_token))
    end
  end


  # PATCH/PUT /statements/1/add_linked_data.json
  def add_linked_data
    s = statement_params
    #  { "statement": {"cache": "[\"#{options[:name]}\",\"#{options[:rdfs_class]}\",\"#{options[:uri]}\"]", "status": "ok", "status_origin": user_name} }

    statement_cache = JSON.parse(@statement.cache)
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
        format.json { redirect_to show_resources_path(rdf_uri: @statement.webpage.rdf_uri, format: :json)}
      else
        format.html { render :edit }
        format.json { render json: @statement.errors, status: :unprocessable_entity }
      end
    end
  end


  # PATCH/PUT /statements/1/remove_linked_data.json
  def remove_linked_data
    s = statement_params
    #  { "statement": {"cache": "[\"#{options[:name]}\",\"#{options[:rdfs_class]}\",\"#{options[:uri]}\"]", "status": "ok", "status_origin": user_name} }

    statement_cache = JSON.parse(@statement.cache)
    uri_to_delete =  JSON.parse(s['cache'])[2]
    class_to_delete = JSON.parse(s['cache'])[1]
    label_to_delete = JSON.parse(s['cache'])[0]

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
  
     #set all statement.selected_individual = false
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

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_statement
    @statement = Statement.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def statement_params
    params.require(:statement).permit(:manual, :cache, :status, :status_origin, :cache_refreshed, :cache_changed, :source_id, :webpage_id, :selected_individual)
  end

  def extract_property_ids rdfs_class_name, property_ids
    # recursive function to traverse tree of properties and add properties of sub-classes with data type of Blank Node or "bnode"
    class_list = rdfs_class_name.split(',')
    class_list.each do |c|
      rdfs_class = RdfsClass.where(name: c).first
      if rdfs_class
        rdfs_class.properties.each do |property|
          property_ids << property.id
          if ((property.value_datatype == "bnode" || property.value_datatype == "xsd:anyURI") && property.expected_class != rdfs_class_name)
            extract_property_ids property.expected_class, property_ids
          end
        end
      end
    end
    return property_ids
  end

  def refresh_webpage_statements webpage, default_language = "en", scrape_options={}
    languages = [webpage.language]
    #if webpage is default_language then add sources with no language to list of languages [webpage.language,'']
    if webpage.language == default_language
      languages << ''
    end
    #get the properties for the rdfs_class of the webpage recursively
    property_ids = extract_property_ids webpage.rdfs_class.name, []
    property_ids.each do |property_id|
      #get the sources for each property (usually one by may have several steps)
      sources = Source.where(website_id: webpage.website, language: languages, property_id: property_id).order(:property_id, :next_step)
      helpers.scrape_sources sources, webpage, scrape_options
    end
  end

  ##
  # Load the statement's source algorithms unless the statement is manual
  def refresh_statement(statement)
    return if statement.manual

    # get the webpage and sources (check if more than one sounce with steps)
    webpage = statement.webpage
    sources = Source.where(id: statement.source_id).or(Source.where(next_step: statement.source_id)).order(:next_step)
    helpers.scrape_sources sources, webpage
  end

  def build_query(rdf_uri:, seedurl:, prop:, status:, selected: nil, selected_individual: nil, source: nil)
    statements = Statement.all

    # filter by a Resource URI
    if rdf_uri.present?
      webpage = Webpage.where(rdf_uri: rdf_uri)
      statements = statements.joins(:source).where(webpage_id: webpage).order( "sources.selected DESC" , "sources.property_id" )
    end
    # filter by seedurl
    if seedurl.present? && seedurl != 'all'
      statements = statements.joins(webpage: :website).where(webpages: { websites: {seedurl:  seedurl }}).order(:id)
    end
    # filter by a property
    if prop.present?
      statements = statements.joins(source: :property).where(sources: { properties: {id: prop }} )
    end
    # filter by status
    if status.present?
      statements = statements.where(status: status)
    end
    # filter by selected
    if selected.present?
      statements = statements.includes(:source).where(sources: { selected: selected } )
    end
     # filter by selected_individual
    if selected_individual.present?
      statements = statements.where(selected_individual: selected_individual )
    end
     # filter by source
    if source.present?
      statements = statements.where(source: source )
    end
    
    statements
  end

  

end
