class StatementsController < ApplicationController
  before_action :set_statement, only: [:show, :edit, :update, :destroy]

  #GET /statements/event.json?uri=
  def event
    # get webpages for uri
    @statements = []
    webpages = Webpage.where(rdf_uri: params[:uri])
    webpages.each do |webpage|
      webpage.statements.each do |statement|
        @statements << statement
      end


    end
  end

  #GET /statements/refresh_uri.json?uri=
  def refresh_uri
    # get webpages for uri
    webpages = Webpage.where(rdf_uri: params[:uri])
    webpages.each do |webpage|
      #get the properties for the laguage of the webpage
      properties = webpage.rdfs_class.properties.where(language: webpage.language)
      properties.each do |property|
        #get the sources for each property (usually one by may have several steps)
        sources = Source.where(website_id: webpage.website, property_id: property.id).order(:property_id, :next_step)
        sources.each do |source|
          url = webpage.url
          url = @next_step_url if !@next_step_url.nil?
          scraped_data = scrape(source,url)
          if source.next_step.nil?
            @next_step_url = nil
            data = format_datatype(scraped_data, property)
            #check for existing statement
            s = Statement.where(webpage_id: webpage.id, property_id: source.property.id)
            if s.count != 1
              Statement.create!(cache:data,webpage_id: webpage.id, property_id: source.property.id)
            else
              #update existing statement
              s.first.update(cache:data,status_origin: "refresh")
            end
          else
            #there is another step
            @next_step_url = scraped_data
            @next_step_url = scraped_data.first if scraped_data.count > 1
          end
        end
      end

    end

    redirect_to statements_url, notice: 'All statements were successfully refreshed.'

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

    def scrape(source, url)
      begin
        algorithm = source.algorithm_value
        agent = Mechanize.new
        agent.user_agent_alias = 'Mac Safari'
        html = agent.get_file  use_wringer(url, source.render_js)
        page = Nokogiri::HTML html

        results_list = []
        algorithm.split(',').each do |a|
          page_data = page.xpath(a.delete_prefix("xpath=")) if a.include? 'xpath'
          page_data = page.css(a.delete_prefix("css="))   if a.include? 'css'
          page_data.each { |d| results_list << d.text}
        end
      rescue => e
        puts "Error in scrape: #{e.inspect}"
        results_list = ["Error scrapping"]
      end
      return results_list
    end


    def use_wringer(url, render_js)
      escaped_url = CGI.escape(url)
      _base_url = "http://footlight-wringer.herokuapp.com"
      if render_js
        path = "/websites/wring?uri=#{escaped_url}&format=raw&include_fragment=true&use_phantomjs=true"
      else
        path = "/websites/wring?uri=#{escaped_url}&format=raw&include_fragment=true"
      end
      return _base_url + path
    end


    def ISO_date(date)
    #  SAMEDI 29 JUILLET 2017, 20 H | GRAND CHAPITEAU
    # --> output "2017-08-29 20:00:00"
    # swap Juillet for July, Aout for August
      date.downcase!
      date.gsub!('juillet','July')
      date.gsub!('août', 'August')
      begin
        d = Time.parse date
        #iso_date =  d.strftime('%F %T')
        iso_date =  d.strftime('%F')
      rescue
        iso_date = "Bad input date: #{date}"
      end
      return iso_date
    end


    def format_datatype (scraped_data, property)
      data = []
      if property.value_datatype == "xsd:date"
        scraped_data.each do |d|
          data << ISO_date(d)
        end
      else
        data = scraped_data
      end
      data = data.first if data.count == 1
      return data
    end
end
