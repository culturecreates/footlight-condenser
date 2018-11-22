class StatementsController < ApplicationController
  before_action :set_statement, only: [:show, :edit, :update, :destroy, :add_linked_data, :remove_linked_data]
  skip_before_action :verify_authenticity_token

  #GET /statements/webpage.json?url=http://
  def webpage
    @statements = []
    webpage = Webpage.where(url: params[:url]).first
    webpage.statements.each do |statement|
      @statements << statement
    end
    @statements.sort
  end

  #PATCH /statements/refresh_webpage.json?url=http://
  def refresh_webpage
    @html_cache = []
    webpage = Webpage.where(url: params[:url]).first
    refresh_webpage_statements(webpage)
    respond_to do |format|
        format.html {redirect_to webpage_statements_path(url: params[:url]), notice: 'All statements were successfully refreshed.'}
        format.json {render json: {message:"statements refreshed"}.to_json }
    end
  end


  #PATCH /statements/refresh_rdf_uri.json?rdf_uri=
  #PATCH /statements/refresh_rdf_uri.json?rdf_uri=&force_scrape_every_hrs=24
  def refresh_rdf_uri
    params[:force_scrape_every_hrs] ||= nil
    @html_cache = []
    webpages = Webpage.where(rdf_uri: params[:rdf_uri])
    webpages.each do |webpage|
      refresh_webpage_statements(webpage, :force_scrape_every_hrs => params[:force_scrape_every_hrs])
    end
    respond_to do |format|
      format.html { redirect_to show_resources_path(rdf_uri: params[:rdf_uri]), notice: 'All statements were successfully refreshed.' }
      format.json { render json: {message:"URIs refreshed"}.to_json }
    end
  end

  # PATCH /statements/1/refresh
  # PATCH /statements/1/refresh.json
  def refresh
    @html_cache = []
    @statement = Statement.where(id: params[:id]).first
    refresh_statement @statement
    respond_to do |format|
      format.html { redirect_to @statement, notice: 'Statement was successfully refreshed.' }
      format.json { render :show, status: :refreshed, location: @statement }
    end
  end


  # GET /statements
  # GET /statements.json
  def index
    if cookies[:seedurl]
      @statements = Statement.joins(webpage: :website).where(webpages: { websites: {seedurl:  cookies[:seedurl]}}).order(:id).paginate(page: params[:page], per_page: params[:per_page])
    else
      @statements = Statement.all.order(:id).paginate(page: params[:page], per_page: params[:per_page])
    end
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

  # PATCH/PUT /statements/1
  # PATCH/PUT /statements/1.json
  def update
    respond_to do |format|
      if @statement.update(statement_params)
        format.html { redirect_to show_resources_path(rdf_uri: @statement.webpage.rdf_uri), notice: 'Statement was successfully updated.' }
        format.json { redirect_to show_resources_path(rdf_uri: @statement.webpage.rdf_uri, format: :json)}
      else
        format.html { render :edit }
        format.json { render json: @statement.errors, status: :unprocessable_entity }
      end
    end
  end


  # PATCH/PUT /statements/1/add_linked_data.json
  def add_linked_data
    s = statement_params
    #  { "statement": {"cache": "[\"#{options[:name]}\",\"#{options[:rdfs_class]}\",\"#{options[:uri]}\"]", "status": "ok", "status_origin": user_name} }

    statement_cache = JSON.parse(@statement.cache)
    statement_cache << [JSON.parse(s['cache'])[0], JSON.parse(s['cache'])[2]]

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
    statement_cache.select! {|linked_data| linked_data[1] != uri_to_delete}
    puts "Delete: #{uri_to_delete} from #{statement_cache}"
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
  def activate
    #get all statements about this property/language for the resource(individual)
    @statement = Statement.find(params[:id])
    @source_id = @statement.source.id
    @property = @statement.source.property
    @language = @statement.source.language
    @webpage =  @statement.webpage
    @website = @webpage.website
    @sources = Source.where(website_id: @website.id, property_id: @property.id, language: @language )

    #set all source selected = false
    @sources.each do |source|
      if source.id != @source_id
        source.update(selected: false)
      else
        source.update(selected: true)
        #?????set all statements with this source to status: updated if in initial status
      end
    end

    respond_to do |format|
        format.html { redirect_to show_resources_path(rdf_uri: @webpage.rdf_uri), notice: 'Statement was successfully activated.' }
        format.json { redirect_to show_resources_path(rdf_uri: @webpage.rdf_uri, format: :json)}
      #  format.json { render "resources/show", rdf_uri: @webpage.rdf_uri}
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
      params.require(:statement).permit(:cache, :status, :status_origin, :cache_refreshed, :cache_changed, :source_id, :webpage_id)
    end

    def refresh_webpage_statements webpage, scrape_options={}
      @html_cache = []
      #get the properties for the rdfs_class of the webpage
      properties = webpage.rdfs_class.properties
      properties.each do |property|
        #get the sources for each property (usually one by may have several steps)
        #if english add sources without a langauge
        if webpage.language == "en"
          sources = Source.where(website_id: webpage.website, language: [webpage.language,''], property_id: property.id).order(:property_id, :next_step)
        else
          sources = Source.where(website_id: webpage.website, language: webpage.language, property_id: property.id).order(:property_id, :next_step)
        end
        scrape_sources sources, webpage, scrape_options
      end
    end

    def refresh_statement statement
      @html_cache = []
      #get the webpage and sources (check if more than one sounce with steps)
      webpage = statement.webpage
      sources = Source.where(id: statement.source_id).or(Source.where(next_step: statement.source_id)).order(:next_step)
      scrape_sources sources, webpage
    end

    def scrape_sources sources, webpage, scrape_options={}

      logger.info("*** Starting scrape with sources:#{sources.inspect} for webpage: #{webpage.inspect}")
      sources.each do |source|
        _scraped_data = helpers.scrape(source, @next_step.nil? ? webpage.url :  @next_step, scrape_options)

        if source.next_step.nil?
          @next_step = nil #clear to break chain of scraping urls
          _data = helpers.format_datatype(_scraped_data, source.property, webpage)

          #add startDate to ArchiveDate in Webpages Table to be able to sort by date and refresh event still to come.
          if source.property.uri == "http://schema.org/startDate"
             _data.class == Array ? last_show_date = _data.last : last_show_date = _data
             if last_show_date.present?
               webpage.archive_date = last_show_date.to_datetime - 24.hours
               if webpage.save
                 logger.debug("*** set archive date for #{webpage.url} to #{webpage.archive_date}")
               else
                 logger.error("*** ERROR: could not save archive date for #{webpage.url} using  #{last_show_date}.")
               end
             end
          end
          s = Statement.where(webpage_id: webpage.id, source_id: source.id)
          if s.count != 1  #create or update database entry
            Statement.create!(cache:_data, webpage_id: webpage.id, source_id: source.id, status: helpers.status_checker(_data, source.property) , status_origin: "condensor_refresh",cache_refreshed: Time.new)
          else
            #check if manual entry and if yes then don't update
            if source.algorithm_value.start_with?("manual=")
              if s.first.status != "missing"
                puts "Skipping update of manual entry"
                next
              else
                puts "Retrying to process manual entry because status is MISSING"
              end
            end
            #model automatically sets cache changed
            logger.info("*** Last step cache: #{_data}")
            s.first.update(cache:_data, cache_refreshed: Time.new)
          end
        else
          #there is another step
          logger.info("*** First step cache: #{_scraped_data}")
          @next_step = _scraped_data.count == 1 ? _scraped_data : _scraped_data.first
        end
      end
    end


end
