class StatementsController < ApplicationController
  before_action :set_statement, only: [:show, :edit, :update, :destroy]

  #GET /statements/event.json?rdf_uri=
  def event
    # get webpages for rdf_uri
    @statements = []
    webpages = Webpage.where(rdf_uri: params[:rdf_uri])
    webpages.each do |webpage|
      webpage.statements.each do |statement|
        @statements << statement
      end
    end
  end

  #GET /statements/webpage.json?uri=
  def webpage
    @statements = []
    webpage = Webpage.where(url: params[:url]).first
    webpage.statements.each do |statement|
      @statements << statement
    end
  end

  #GET /statements/refresh_webpage.json?url=
  def refresh_webpage
    webpage = Webpage.where(url: params[:url]).first
    refresh_statements(webpage)
    redirect_to webpage_statements_path(url: params[:url]), notice: 'All statements were successfully refreshed.'
  end

  #GET /statements/refresh_rdf_uri.json?uri=
  def refresh_rdf_uri
    webpages = Webpage.where(rdf_uri: params[:rdf_uri])
    webpages.each do |webpage|
      refresh_statements(webpage)
    end
    redirect_to event_statements_path(rdf_uri: params[:rdf_uri]), notice: 'All statements were successfully refreshed.'
  end


  # GET /statements
  # GET /statements.json
  def index
    @statements = Statement.all
  end

  # GET /statements/1
  # GET /statements/1.json
  def show
  end

  # GET /statements/new
  def new
    @statement = Statement.new
  end

  # GET /statements/1/edit
  def edit
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
        format.html { redirect_to @statement, notice: 'Statement was successfully updated.' }
        format.json { render :show, status: :ok, location: @statement }
      else
        format.html { render :edit }
        format.json { render json: @statement.errors, status: :unprocessable_entity }
      end
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
      params.require(:statement).permit(:cache, :status, :status_origin, :cache_refreshed, :cache_changed, :property_id, :webpage_id)
    end

    def refresh_statements(webpage)
      #get the properties for the rdfs_class and laguage of the webpage
      properties = webpage.rdfs_class.properties.where(language: webpage.language)
      properties.each do |property|
        #get the sources for each property (usually one by may have several steps)
        sources = Source.where(website_id: webpage.website, property_id: property.id).order(:property_id, :next_step)
        sources.each do |source|
          _scraped_data = helpers.scrape(source, @next_step.nil? ? webpage.url :  @next_step)
          if source.next_step.nil?
            @next_step = nil #clear to break chain of scraping urls
            _data = helpers.format_datatype(_scraped_data, property)
            s = Statement.where(webpage_id: webpage.id, property_id: source.property.id)
            if s.count != 1  #create or update database entry
              Statement.create!(cache:_data,webpage_id: webpage.id, property_id: source.property.id)
            else
              s.first.update(cache:_data,status_origin: "refresh")
            end
          else
            #there is another step
            @next_step = _scraped_data.count == 1 ? _scraped_data : _scraped_data.first
          end
        end
      end
    end



end
