class WebpagesController < ApplicationController
  include HarmonizedIndexParams

  skip_before_action :verify_authenticity_token
  before_action :set_webpage, only: [:show, :edit, :update, :destroy]

  # GET /webpages
  # GET /webpages.json
  def index
    @seedurl, website = normalized_seedurl_website
    @current_website = website
    cookies[:seedurl] = @seedurl if @seedurl.present?

    index_params = harmonized_index_params(
      allowed_filters: Webpages::IndexQuery::FILTER_KEYS,
      allowed_sorts: Webpages::IndexQuery::SORT_COLUMNS.keys,
      default_sort: Webpages::IndexQuery::DEFAULT_SORT,
      default_direction: Webpages::IndexQuery::DEFAULT_DIRECTION,
      default_per_page: Webpages::IndexQuery::DEFAULT_PER_PAGE,
      max_per_page: Webpages::IndexQuery::MAX_PER_PAGE
    )

    canonical = harmonized_index_canonical_params(
      index_params,
      default_sort: Webpages::IndexQuery::DEFAULT_SORT,
      default_direction: Webpages::IndexQuery::DEFAULT_DIRECTION,
      default_per_page: Webpages::IndexQuery::DEFAULT_PER_PAGE,
      preserve: @seedurl.present? ? { seedurl: @seedurl } : {}
    )
    raw = harmonized_index_raw_params(
      allowed_filters: Webpages::IndexQuery::FILTER_KEYS,
      preserve: %w[seedurl sort direction page per_page]
    )
    return redirect_to(webpages_path(canonical)) if canonical != raw

    @filters = index_params[:filters]
    query_filters = @filters.merge(website_id: website.id) if website.present?
    query_filters ||= @filters
    @sort = index_params[:sort]
    @direction = index_params[:direction]
    @pagination = {
      page: index_params[:page],
      per_page: index_params[:per_page]
    }
    filtered_scope = Webpages::IndexQuery.scope(filters: query_filters)
    @webpages = Webpages::IndexQuery.call(
      filters: query_filters,
      sort: @sort,
      direction: @direction,
      page: @pagination[:page],
      per_page: @pagination[:per_page]
    )

    @sortable_filters = @filters.merge(per_page: @pagination[:per_page])
    @sortable_filters[:seedurl] = @seedurl if @seedurl.present?
    @total_webpages_count = Webpage.count
    @website_webpages_total_count = website.present? ? website.webpages.count : nil
    @filtered_webpages_count = filtered_scope.count
    @visible_webpages_count = @webpages.length
    @webpage_summary = nil
    if website.present?
      @webpage_summary = Distillator::WebsiteWebpageSummary.for_websites([website.id])[website.id]
    end

    @webpage_cache_link_rows = @webpages.each_with_object({}) do |webpage, rows|
      rows[webpage.id] = helpers.webpage_cache_links(webpage)
    end
    @show_distillator_cache_column = false
    @webpage_table_headers = HarmonizedTableHeaders.webpages(
      show_distillator_cache_column: @show_distillator_cache_column
    )

    publishable_ids = Webpage.publishable.where(id: @webpages.map(&:id)).pluck(:id).to_set
    @publishable = @webpages.each_with_object({}) do |webpage, values|
      values[webpage.id] = publishable_ids.include?(webpage.id) ? "Yes" : "No"
    end
  end

  # GET /webpages/1
  # GET /webpages/1.json
  def show
  end

  # GET /webpages/new
  def new
    @webpage = Webpage.new
    @rdfs_classes = RdfsClass.all
    @jsonld_outputs = JsonldOutput.all
  end

  # GET /webpages/1/edit
  def edit
    @rdfs_classes = RdfsClass.all
    @jsonld_outputs = JsonldOutput.all
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
        @rdfs_classes = RdfsClass.all
        @jsonld_outputs = JsonldOutput.all
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
    rdfs_class_id = rdfs_class.id if rdfs_class.present?
    website = Website.where(seedurl: p["seedurl"]).first
    website_id = website.id if website.present?

    @webpage = Webpage.new(url: url, rdfs_class_id: rdfs_class_id, rdf_uri: rdf_uri, language: language, website_id: website_id)
    if @webpage.save
      render :show_api, status: :created, location: @webpage
    else
      render json: @webpage.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /webpages/1
  # PATCH/PUT /webpages/1.json
  def update   # Set jsonld_output_id to nil if the parameter is not present or is empty
    if params[:webpage][:jsonld_output_id].blank?
      params[:webpage][:jsonld_output_id] = nil
    end
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
    params.require(:webpage).permit(:url, :language, :rdf_uri, :rdfs_class_id, :jsonld_output_id, :website_id, :archive_date)
  end

  def webpage_api_params
    params.require(:webpage).permit(:url, :language, :rdf_uri, :rdfs_class, :seedurl)
  end

  def normalized_seedurl_website
    seedurl = params[:seedurl].presence || cookies[:seedurl].presence
    return [nil, nil] if seedurl.blank? || seedurl == "all"

    website = Website.find_by(seedurl: seedurl)
    website.present? ? [seedurl, website] : [nil, nil]
  end

end
