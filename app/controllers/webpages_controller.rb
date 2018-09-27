class WebpagesController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_webpage, only: [:show, :edit, :update, :destroy]


  # GET /webpages
  # GET /webpages.json
  def index
    if params[:seedurl]
      @webpages = Webpage.where(website_id: Website.where(seedurl: params[:seedurl]).first.id).where(rdfs_class: 1)
    else
      if cookies[:seedurl]
        @webpages = Webpage.where(website_id: Website.where(seedurl: cookies[:seedurl]).first.id)
      else
        @webpages = Webpage.all
      end
    end


  end

  # GET /webpages/website?seedurl=
  def website
    @website = Website.where(seedurl: params[:seedurl]).first
    @webpages = Webpage.where(website_id: @website.id)
  end

  # GET /webpages/1
  # GET /webpages/1.json
  def show
  end

  # GET /webpages/new
  def new
    @webpage = Webpage.new
    @websites = Website.all
    @rdfs_classes = RdfsClass.all
  end

  # GET /webpages/1/edit
  def edit
    @websites = Website.all
    @rdfs_classes = RdfsClass.all
  end

  # POST /webpages
  # POST /webpages.json
  def create
    @webpage = Webpage.new(webpage_params)

    respond_to do |format|
      if @webpage.save
        format.html { redirect_to @webpage, notice: 'Webpage was successfully created.' }
        format.json { render :show, status: :created, location: @webpage }
      else
        format.html { render :new }
        format.json { render json: @webpage.errors, status: :unprocessable_entity }
      end
    end
  end

  # POST /webpages/create_api.json
  def create_api
    p = webpage_api_params
    url = p["url"]
    rdf_uri = p["rdf_uri"]
    language = p["language"]

    rdfs_class = RdfsClass.where(name: p["rdfs_class"]).first
    rdfs_class_id = rdfs_class.id if !rdfs_class.blank?
    website = Website.where(seedurl: p["seedurl"]).first
    website_id = website.id if !website.blank?
    
    @webpage = Webpage.new(url: url, rdfs_class_id: rdfs_class_id, rdf_uri: rdf_uri, language: language, website_id: website_id)
    if @webpage.save
      render :show, status: :created, location: @webpage
    else
      render json: @webpage.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /webpages/1
  # PATCH/PUT /webpages/1.json
  def update
    respond_to do |format|
      if @webpage.update(webpage_params)
        format.html { redirect_to @webpage, notice: 'Webpage was successfully updated.' }
        format.json { render :show, status: :ok, location: @webpage }
      else
        format.html { render :edit }
        format.json { render json: @webpage.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /webpages/1
  # DELETE /webpages/1.json
  def destroy
    @webpage.destroy
    respond_to do |format|
      format.html { redirect_to webpages_url, notice: 'Webpage was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_webpage
      @webpage = Webpage.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def webpage_params
      params.require(:webpage).permit(:url, :language, :rdf_uri, :rdfs_class_id, :website_id)
    end

    def webpage_api_params
      params.require(:webpage).permit(:url, :language, :rdf_uri, :rdfs_class, :seedurl)
    end



end
