class WebsitesController < ApplicationController
  include FilterableIndex
  include SortableIndex

  FILTER_KEYS = %i[q seed_filter default_language graph_name distillator_mode].freeze

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
    return render json: Distillator::FetchCacheStore.lookup_by_term(params[:term]) if wringer_lookup_request?

    requested_rollout_mode = params[:distillator_mode].presence
    cleaned = extract_allowed_filters(params, FILTER_KEYS)
    cleaned[:distillator_mode] = helpers.normalize_website_rollout_filter(cleaned[:distillator_mode])

    canonical = cleaned.merge(
      sort: params[:sort],
      direction: params[:direction]
    ).compact.stringify_keys

    raw = params.to_unsafe_h.slice(
      *FILTER_KEYS.map(&:to_s),
      "sort",
      "direction"
    ).compact

    normalized_raw = extract_allowed_filters(raw, FILTER_KEYS).merge(
      sort: raw["sort"],
      direction: raw["direction"]
    ).compact.stringify_keys
    normalized_raw["distillator_mode"] = helpers.normalize_website_rollout_filter(normalized_raw["distillator_mode"])
    normalized_raw.compact!

    invalid_rollout_filter = requested_rollout_mode.present? && cleaned[:distillator_mode].nil?
    return redirect_to(websites_path(canonical)) if invalid_rollout_filter || canonical != normalized_raw

    @filters = cleaned

    @current_sort = params[:sort].presence
    @current_direction = params[:direction].presence

    @websites = Website.all

    if @filters[:q]
      keyword = "%#{@filters[:q].downcase}%"
      @websites = @websites.where("LOWER(name) LIKE ?", keyword)
    end

    if @filters[:seed_filter]
      keyword = "%#{@filters[:seed_filter].downcase}%"
      @websites = @websites.where("LOWER(seedurl) LIKE ?", keyword)
    end

    if @filters[:default_language]
      @websites = @websites.where(default_language: @filters[:default_language])
    end

    if @filters[:graph_name]
      keyword = "%#{@filters[:graph_name].downcase}%"
      @websites = @websites.where("LOWER(graph_name) LIKE ?", keyword)
    end

    case @filters[:distillator_mode]
    when "unknown"
      @websites = @websites.where(distillator_mode: [nil, ""])
    when nil
      nil
    else
      @websites = @websites.where(distillator_mode: @filters[:distillator_mode])
    end

    @rollout_counts = Website.group(:distillator_mode).count

    @total_statements = Statement.all.count
    @statements_errors = Statement.where("cache LIKE ?", "%error%")
                                   .where(cache_refreshed: [(Time.zone.now - 24.hours)..(Time.zone.now)])
                                   .count

    @statements_grouped = Statement.joins(webpage: :website).group(:seedurl).count
    @statements_refreshed_24hr = Statement.joins(webpage: :website).where(cache_refreshed: [(Time.zone.now - 24.hours)..(Time.zone.now)]).group(:seedurl).count
    @statements_updated_24hr = Statement.joins(webpage: :website).where(cache_changed: [(Time.zone.now - 24.hours)..(Time.zone.now)]).group(:seedurl).count
    @webpages = Webpage.group(:website_id).count
    @flags = Statement.joins(webpage: :website).where(status: ["problem"], selected_individual: true, webpages: { rdfs_class_id: 1}).group(:seedurl).count
    @updated = Statement.joins(webpage: :website).where(status: "updated", selected_individual: true, webpages: { rdfs_class_id: 1}).group(:seedurl).count

    if computed_sort?
      @websites = sort_in_memory(@websites)
    else
      @websites = @websites.order(sort_column => sort_direction.to_sym)
    end
  
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

  def delete_all_event_webpages
    @webpages = Webpage.where(website_id: params[:id], rdfs_class_id: RdfsClass.where(name: "Event"))
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
    params.require(:website).permit(:name, :seedurl, :graph_name, :default_language, :schedule_every_days, :schedule_time, :last_refresh, :distillator_mode)
  end

  def sort_column
    allowed_columns = %w[
      name seedurl default_language schedule_every_days
      schedule_time last_refresh graph_name
      webpages_count statements_count refreshed_24h updated_24h
    ]
    normalized_sort_param(params[:sort], allowed: allowed_columns, default: "name")
  end

  def sort_direction
    normalized_direction_param(params[:direction], default: "asc")
  end

  def computed_sort?
    %w[webpages_count statements_count refreshed_24h updated_24h].include?(sort_column)
  end

  def sort_in_memory(relation)
    direction = sort_direction == "desc" ? -1 : 1

    relation.to_a.sort_by do |website|
      value =
        case sort_column
        when "webpages_count"
          @webpages[website.id] || 0
        when "statements_count"
          @statements_grouped[website.seedurl] || 0
        when "refreshed_24h"
          @statements_refreshed_24hr[website.seedurl] || 0
        when "updated_24h"
          @statements_updated_24hr[website.seedurl] || 0
        else
          0
        end

      direction == 1 ? value : -value
    end
  end

  def wringer_lookup_request?
    params[:term].present? && request.format.json?
  end

  def wring_invalid_response
    case params[:format].to_s
    when "html"
      redirect_to websites_path, notice: "INVALID params for wringing."
    else
      head :no_content
    end
  end
end
