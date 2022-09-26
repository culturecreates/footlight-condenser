class WebsitesController < ApplicationController
  before_action :set_website, only: [:show, :edit, :update, :destroy, :delete_all_statements]

  def test_api
    @websites = Website.all.order(:name)
  end

  # GET /webpages/events.json?seedurl=
  def events
    @events = []
    event_uris = helpers.get_uris params[:seedurl], "Event"
    event_uris.each do |event_uri|
      @events << {rdf_uri: event_uri[:uri] }
    end
    cookies[:seedurl] = params[:seedurl]
  end

  # GET /webpages/places.json?seedurl=
  def places
    @places = []
    place_uris = helpers.get_uris params[:seedurl], "Place"
    place_uris.each do |place_uri|
      @places << {rdf_uri: place_uri[:uri]}
    end
  end

  # GET /websites
  # GET /websites.json
  def index
    if params[:q]
      like_keyword = "%#{params[:q]}%"
      @websites = Website.where("name LIKE ?", like_keyword)
    else
      @websites = Website.all.order(:name)
    end
    @total_statements = Statement.all.count
    @statements_errors = Statement.where("cache LIKE ?", "%error%")
                                   .where(cache_refreshed: [(Time.now - 24.hours)..(Time.now)])
                                   .count

    @statements_grouped = Statement.joins(source: :website).group(:seedurl).count
    @statements_refreshed_24hr = Statement.joins(source: :website).where(cache_refreshed: [(Time.now - 24.hours)..(Time.now)]).group(:seedurl).count
    @statements_updated_24hr = Statement.joins(source: :website).where(cache_changed: [(Time.now - 24.hours)..(Time.now)]).group(:seedurl).count
    @webpages = Webpage.group(:website).count
  end

  # GET /websites/1
  # GET /websites/1.json
  def show
    cookies[:seedurl] = @website.seedurl
  end

  # GET /websites/new
  def new
    @website = Website.new
  end

  # GET /websites/1/edit
  def edit
  end

  # POST /websites
  # POST /websites.json
  def create
    @website = Website.new(website_params)

    respond_to do |format|
      if @website.save
        format.html { redirect_to @website, notice: 'Website was successfully created.' }
        format.json { render :show, status: :created, location: @website }
      else
        format.html { render :new }
        format.json { render json: @website.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /websites/1
  # PATCH/PUT /websites/1.json
  def update
    respond_to do |format|
      if @website.update(website_params)
        format.html { redirect_to @website, notice: 'Website was successfully updated.' }
        format.json { render :show, status: :ok, location: @website }
      else
        format.html { render :edit }
        format.json { render json: @website.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /websites/1
  # DELETE /websites/1.json
  def destroy
    @website.destroy
    cookies.delete :seedurl
    respond_to do |format|
      format.html { redirect_to websites_url, notice: 'Website was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  def delete_all_statements
    @statements = Statement.joins(webpage: :website).where(webpages: { website: @website})
    @statements.destroy_all
    respond_to do |format|
      format.html { redirect_to websites_url, notice: 'ALL website statements were successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  def delete_all_webpages
    @webpages = Webpage.where(website_id: params[:id])
    @webpages.destroy_all
    respond_to do |format|
      format.html { redirect_to websites_url, notice: 'ALL webpages were successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_website
    @website = Website.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def website_params
    params.require(:website).permit(:name, :seedurl, :graph_name, :default_language, :schedule_every_days, :schedule_time, :last_refresh)
  end
end
