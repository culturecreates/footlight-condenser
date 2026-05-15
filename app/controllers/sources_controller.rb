class SourcesController < ApplicationController
  include HarmonizedIndexParams

  before_action :set_source, only: [:show, :edit, :update, :destroy]
  skip_before_action :verify_authenticity_token

  # GET /sources
  # GET /sources.json
  def index
    @seedurl = params[:seedurl].presence || cookies[:seedurl].presence
    @website = find_source_index_website(@seedurl)
    return render_missing_sources_website(@seedurl) if @seedurl.present? && @seedurl != "all" && @website.nil?

    cookies[:seedurl] = @seedurl if @website.present?
    @website_id = @website&.id

    index_params = harmonized_index_params(
      allowed_filters: Sources::IndexQuery::FILTER_KEYS,
      allowed_sorts: Sources::IndexQuery::SORT_COLUMNS.keys,
      default_sort: Sources::IndexQuery::DEFAULT_SORT,
      default_direction: Sources::IndexQuery::DEFAULT_DIRECTION,
      default_per_page: Sources::IndexQuery::DEFAULT_PER_PAGE,
      max_per_page: Sources::IndexQuery::MAX_PER_PAGE
    )

    canonical = harmonized_index_canonical_params(
      index_params,
      default_sort: Sources::IndexQuery::DEFAULT_SORT,
      default_direction: Sources::IndexQuery::DEFAULT_DIRECTION,
      default_per_page: Sources::IndexQuery::DEFAULT_PER_PAGE,
      preserve: @seedurl.present? && @seedurl != "all" ? { seedurl: @seedurl } : {}
    )
    raw = harmonized_index_raw_params(
      allowed_filters: Sources::IndexQuery::FILTER_KEYS,
      preserve: %w[seedurl sort direction page per_page]
    )
    return redirect_to(sources_path(canonical)) if canonical != raw

    @filters = index_params[:filters]
    query_filters = @filters.merge(website_id: @website.id) if @website.present?
    query_filters ||= @filters
    @sort = index_params[:sort]
    @direction = index_params[:direction]
    @pagination = {
      page: index_params[:page],
      per_page: index_params[:per_page]
    }
    @sources = Sources::IndexQuery.call(
      filters: query_filters,
      sort: @sort,
      direction: @direction,
      page: @pagination[:page],
      per_page: @pagination[:per_page]
    )
    @sortable_filters = @filters.merge(per_page: @pagination[:per_page])
    @source_table_headers = HarmonizedTableHeaders.sources
    @source_quick_filters = source_index_quick_filters
    @rdfs_classes = RdfsClass.all
  end


  # GET /sources/website?id=
  def website
    @sources = Source.where(website_id: params[:id])
    @website = Website.where(id: params[:id]).first
  end

  # GET /sources/1
  # GET /sources/1.json
  def show 
  end


  # GET /sources/new[?rdfs_class_id=]
  def new
    @source = Source.new
    @websites = Website.all
    @properties = Property.all
    @rdfs_class_id = params[:rdfs_class_id] || 1 #default to event class
    @rdfs_class_name = RdfsClass.find(@rdfs_class_id).name
  end

  # GET /sources/1/edit
  def edit
    @websites = Website.all
    @properties = Property.all
    @rdfs_class_id = @source.property.rdfs_class_id
    @rdfs_class_name = @source.property.rdfs_class.name
  end

  # POST /sources
  # POST /sources.json
  # manually create sources for all websites using:
  #   > website_hash = Website.all.map {|w| {website_id: w.id}}
  #   > Source.create(website_hash) {|s| s.algorithm_value = ''; s.selected = true; s.property_id=XX; s.render_js = false ; s.language = ''}
  def create
    @source = Source.new(source_params)

    respond_to do |format|
      if @source.save
        format.html { redirect_to @source, notice: 'Source was successfully created.' }
        format.json { render :show, status: :created, location: @source }
      else
        format.html { render :new }
        format.json { render json: @source.errors, status: :unprocessable_entity }
      end
    end
  end

  ## 
  # Copy all sources from another website
  # POST /sources/copy?from_website_id=&to_website_id=
  def copy
    # Get all sources from website
    website = Website.find(params[:to_website_id])
    sources = Source.where(website: params[:from_website_id])
    sources.each do |source|
      new_source = website.sources.new
      if new_source.update(source.attributes.except("id","website_id","created_at","updated_at"))
        Rails.logger.debug "Created new_source #{new_source.property_id}"
        next
      else
        Rails.logger.debug "failed to update source.inspect "
      end
    end
    redirect_to sources_url, notice: 'Sources added.' 
  end

  # PATCH/PUT /sources/1
  # PATCH/PUT /sources/1.json
  def update
    respond_to do |format|
      if @source.update(source_params)
        format.html { redirect_to @source, notice: 'Source was successfully updated.' }
        format.json { render :show, status: :ok, location: @source }
      else
        format.html { render :edit }
        format.json { render json: @source.errors, status: :unprocessable_entity }
      end
    end
  end


  # DELETE /sources/1
  # DELETE /sources/1.json
  # Manually delete on Heroku using:
  #    > Source.where(algorithm_value: ' ', created_at: [Time.now - 1.hour..Time.now + 10.years]).delete_all
  def destroy
    @source.destroy
    respond_to do |format|
      format.html { redirect_to sources_url, notice: 'Source was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_source
    @source = Source.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def source_params
    params.require(:source).permit(:algorithm_value, :label, :language, :selected, :selected_by, :render_js, :property_id, :website_id, :auto_review)
  end

  def find_source_index_website(seedurl)
    return nil if seedurl.blank? || seedurl == "all"

    Website.find_by(seedurl: seedurl)
  end

  def render_missing_sources_website(seedurl)
    respond_to do |format|
      format.html do
        flash.now[:alert] = "No website found for seedurl: #{seedurl}"
        @sources = Source.none
        @website_id = nil
        @seedurl = nil
        @filters = {}
        @sort = Sources::IndexQuery::DEFAULT_SORT
        @direction = Sources::IndexQuery::DEFAULT_DIRECTION
        @pagination = { page: 1, per_page: Sources::IndexQuery::DEFAULT_PER_PAGE }
        @sortable_filters = @filters.merge(per_page: @pagination[:per_page])
        @source_table_headers = HarmonizedTableHeaders.sources
        @source_quick_filters = []
        @rdfs_classes = RdfsClass.all
        render :index
      end
      format.json { render json: {error: "Website not found"}, status: :not_found }
    end
  end

  def source_index_quick_filters
    [
      { label: "Website defaults", params: quick_filter_params(selected: "true") },
      { label: "Alternatives", params: quick_filter_params(selected: "false") },
      { label: "Rendered fetch", params: quick_filter_params(render_js: "true") },
      { label: "Auto review", params: quick_filter_params(auto_review: "true") }
    ]
  end

  def quick_filter_params(overrides = {})
    base = @filters.slice(:term, :language, :property_id).merge(overrides)
    base[:seedurl] = @seedurl if @seedurl.present? && @seedurl != "all"
    base
  end
end
