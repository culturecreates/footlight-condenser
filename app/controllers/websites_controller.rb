class WebsitesController < ApplicationController
  include FilterableIndex
  include SortableIndex

  FILTER_KEYS = %i[q seed_filter default_language graph_name distillator_mode cohort view validation retry_transition_batch_id].freeze
  DASHBOARD_KEYS = %i[dashboard metrics action_filter transition_website_id].freeze
  DASHBOARDS = %w[action information].freeze
  INDEX_VIEWS = %w[all preferred].freeze

  before_action :set_website, only: [:copy_for_qa, :show, :edit, :update, :destroy, :delete_all_statements, :activate_after_review, :activate_anyway, :confirm_cutover, :preference]

  # POST /websites/:id/copy_for_qa — creates a disabled, unpublished website.
  def copy_for_qa
    unless Rails.env.development? || Rails.env.test? || Distillator::TransitionRuntime.staging?
      return head :forbidden
    end

    begin
      copy = Websites::CreateTestCopy.call(source: @website, seedurl: params[:test_copy_seedurl].presence ||
        Websites::CreateTestCopy.suggest_seedurl(@website.seedurl)).website
      redirect_to website_path(copy), notice: "QA copy created; scheduling and publishing are disabled.", status: :see_other
    rescue Websites::CreateTestCopy::InvalidCopy, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      redirect_to website_path(@website), alert: "Copy failed: #{error.message}", status: :see_other
    end
  end

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

    html_dashboard = request.format.html? || request.format == Mime::ALL
    requested_rollout_mode = params[:distillator_mode].presence
    requested_cohort = params[:cohort].presence
    requested_view = params[:view].presence
    filter_keys = html_dashboard ? FILTER_KEYS + DASHBOARD_KEYS : FILTER_KEYS
    cleaned = extract_allowed_filters(params, filter_keys)
    cleaned[:distillator_mode] = helpers.normalize_website_rollout_filter(cleaned[:distillator_mode])
    cleaned[:cohort] = helpers.normalize_website_cohort_filter(cleaned[:cohort])
    cleaned[:view] = cleaned[:view].presence_in(INDEX_VIEWS)
    cleaned[:validation] = cleaned[:validation].presence_in(Distillator::WebsiteValidationHistory::FILTERS.keys)

    canonical = cleaned.merge(
      sort: params[:sort],
      direction: params[:direction]
    ).compact.stringify_keys

    raw = params.to_unsafe_h.slice(
      *filter_keys.map(&:to_s),
      "sort",
      "direction"
    ).compact

    normalized_raw = extract_allowed_filters(raw, filter_keys).merge(
      sort: raw["sort"],
      direction: raw["direction"]
    ).compact.stringify_keys
    normalized_raw["distillator_mode"] = helpers.normalize_website_rollout_filter(normalized_raw["distillator_mode"])
    normalized_raw["cohort"] = helpers.normalize_website_cohort_filter(normalized_raw["cohort"])
    normalized_raw["view"] = normalized_raw["view"].presence_in(INDEX_VIEWS)
    normalized_raw["validation"] = normalized_raw["validation"].presence_in(Distillator::WebsiteValidationHistory::FILTERS.keys)
    normalized_raw.compact!

    invalid_rollout_filter = requested_rollout_mode.present? && cleaned[:distillator_mode].nil?
    invalid_cohort_filter = requested_cohort.present? && cleaned[:cohort].nil?
    invalid_view = requested_view.present? && cleaned[:view].nil?
    return redirect_to(websites_path(canonical)) if invalid_rollout_filter || invalid_cohort_filter || invalid_view || canonical != normalized_raw

    @filters = cleaned.compact
    configure_dashboard if html_dashboard
    if @filters[:retry_transition_batch_id]
      @retry_transition_batch = Distillator::TransitionBatch.find(@filters[:retry_transition_batch_id])
      @retry_website_ids = @retry_transition_batch.retry_website_ids
      @filters[:view] = "all"
    end
    @default_website_view = html_dashboard ? (cookies.signed[:website_default_view].presence_in(INDEX_VIEWS) || "all") : "all"
    @website_index_view = @filters[:view] || @default_website_view
    # Keep an explicit All override through sorting when Preferred is the default.
    @filters[:view] = @website_index_view if @filters[:view].present? || @default_website_view != "all"
    @preferred_count = Website.where(preferred: true).count

    @current_sort = params[:sort].presence
    @current_direction = params[:direction].presence

    @websites = Website.all
    @websites = @websites.where(id: @retry_website_ids) if @retry_transition_batch
    @websites = @websites.where(id: @dashboard_selection_id) if @dashboard_selection_id
    @websites = @websites.where(preferred: true) if @website_index_view == "preferred"

    if @filters[:q]
      keyword = website_search_pattern(@filters[:q])
      @websites = @websites.where("LOWER(name) LIKE ? OR LOWER(seedurl) LIKE ?", keyword, keyword)
    end

    if @filters[:seed_filter]
      keyword = website_search_pattern(@filters[:seed_filter])
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
    when "invalid_on_staging"
      @websites = Distillator::TransitionRuntime.staging_invalid_rollout_mode_scope(@websites)
    when nil
      nil
    else
      @websites = @websites.where(distillator_mode: @filters[:distillator_mode])
    end

    if @filters[:cohort].present?
      @websites = @websites.to_a.select { |website| helpers.website_matches_cohort_filter?(website, @filters[:cohort]) }
    end

    @transition_eligible_ids = Distillator::EventSiteSelection.eligible_ids(@websites)
    website_rows = @websites.to_a
    if html_dashboard || @filters[:validation] || params[:inventory_freshness] == "true"
      @inventory_data_as_of = Time.current
      inventories = Distillator::WebsiteInventoryFreshness.for_websites(website_rows.map(&:id), as_of: @inventory_data_as_of, diagnostics: html_dashboard)
      @inventory_freshness = inventories if html_dashboard || params[:inventory_freshness] == "true"
    end
    if html_dashboard || @filters[:validation]
      @validation_summaries = Distillator::WebsiteValidationHistory.for_websites(website_rows, inventories: inventories)
      if @filters[:validation]
        @websites = website_rows.select do |site|
          summary = @validation_summaries.fetch(site.id)
          (@transition_eligible_ids.include?(site.id) || summary.last_validation || summary.last_pass || summary.attention || summary.cutover) && summary.matches?(@filters[:validation])
        end
        @transition_eligible_ids &= @websites.map(&:id)
      end
    end
    @rollout_counts = Website.group(:distillator_mode).count

    @total_statements = Statement.all.count

    @statements_grouped = Statement.joins(webpage: :website).group(:seedurl).count
    @statements_refreshed_24hr = Statement.joins(webpage: :website).where(cache_refreshed: [(Time.zone.now - 24.hours)..(Time.zone.now)]).group(:seedurl).count
    @statements_updated_24hr = Statement.joins(webpage: :website).where(cache_changed: [(Time.zone.now - 24.hours)..(Time.zone.now)]).group(:seedurl).count
    website_ids = Array(@websites).map(&:id)
    if html_dashboard
      @recent_error_cache_count = Statement.where("cache LIKE ?", "%error%")
        .where(cache_refreshed: 24.hours.ago..Time.current).count
      @missed_event_counts = MonitoringIssue.open_issues.where(kind: "possible_missed_event",
        seedurl: Website.where(id: website_ids).select(:seedurl)).group(:seedurl).count
    end
    @webpage_summaries = Distillator::WebsiteWebpageSummary.for_websites(website_ids)
    @flags = Statement.joins(webpage: :website).where(status: ["problem"], selected_individual: true, webpages: { rdfs_class_id: 1}).group(:seedurl).count
    @updated = Statement.joins(webpage: :website).where(status: "updated", selected_individual: true, webpages: { rdfs_class_id: 1}).group(:seedurl).count

    if computed_sort?
      @websites = sort_in_memory(@websites)
    elsif @websites.is_a?(Array)
      @websites = @websites.sort_by { |website| [website.public_send(sort_column).to_s.downcase, website.id] }
      @websites.reverse! if sort_direction == "desc"
    else
      @websites = @websites.order(sort_column => sort_direction.to_sym).order(id: :asc)
    end

    if html_dashboard
      @dashboard_running = Distillator::WebsiteActionSummary.running_for(website_ids)
      if @dashboard == "action"
        prepare_action_dashboard
      else
        @website_rendered_fetch = Distillator::WebsiteRenderedFetchSummary.for_websites(website_ids)
      end
    end
  end

  def preference
    value = params.require(:preferred)
    return head :bad_request unless [true, false, "0", "1", "true", "false"].include?(value)

    # A display preference must not run scheduling, rollout or monitorable callbacks.
    @website.update_columns(preferred: Distillator::BooleanParam.parse(value))
    redirect_to safe_return_to_param || websites_path, status: :see_other
  end

  def website_search_pattern(value)
    pattern = Website.sanitize_sql_like(value.downcase).gsub("*", "%")
    value.include?("*") ? pattern : "%#{pattern}%"
  end
  private :website_search_pattern

  def default_view
    value = params.require(:view)
    return head :bad_request unless INDEX_VIEWS.include?(value)

    cookies.permanent.signed[:website_default_view] = { value: value, httponly: true, same_site: :lax, secure: request.ssl? }
    preserved = extract_allowed_filters(params, FILTER_KEYS + DASHBOARD_KEYS).merge(sort: params[:sort], direction: params[:direction])
    redirect_to websites_path(preserved.merge(view: value).compact), status: :see_other
  end

  def default_dashboard
    value = params.require(:dashboard)
    return head :bad_request unless DASHBOARDS.include?(value)

    cookies.permanent.signed[:website_default_dashboard] = { value: value, httponly: true, same_site: :lax, secure: request.ssl? }
    preserved = extract_allowed_filters(params, FILTER_KEYS + DASHBOARD_KEYS).merge(sort: params[:sort], direction: params[:direction])
    redirect_to websites_path(preserved.compact), status: :see_other
  end

  # GET /websites/1
  # GET /websites/1.json
  def show
    cookies[:seedurl] = @website.seedurl
    return unless request.format.html?

    @validation_summary = website_validation_summary if @website.distillator_mode == "active"
    @migration_baselines = Distillator::MigrationBaseline.where(website: @website).latest_first.includes(:validation_run).to_a
    @validation_workflows = Distillator::WebsiteValidationHistory.workflows([@website.id]).to_a
    @validation_profile = params[:validation_profile].presence_in(%w[all light thorough audit])
    @site_check_passes = Distillator::WebsiteValidationHistory.site_check_passes([@website]).select do |pass|
      @validation_profile.in?([nil, "all", pass.profile])
    end
    if @validation_profile && @validation_profile != "all"
      @validation_workflows.select! do |item|
        (item.batch.audit? ? "audit" : item.batch.check_profile) == @validation_profile
      end
    end
    runs = @validation_workflows.flat_map { |item| [item.pre_run_id, item.post_run_id] }.compact
    @validation_page_counts = Distillator::TransitionEvidence.where(transition_run_id: runs, check_kind: "statement_delta")
      .latest_first.pluck(:transition_run_id, Arel.sql("details ->> 'compared_webpage_count'"))
      .each_with_object({}) { |(id, count), out| out[id] ||= count }
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
    @website = Website.new

    respond_to do |format|
      result = Distillator::RolloutTransition.call(
        website: @website,
        to_mode: website_params[:distillator_mode],
        actor: rollout_actor,
        reason: params[:reason],
        attributes: website_params.to_h
      )

      if result.success?
        format.html { redirect_to @website, notice: 'Website was successfully created.' }
        format.json { render :show, status: :created, location: @website }
      else
        flash.now[:alert] = result.errors.join(", ") if result.errors.any?
        format.html { render :new }
        format.json { render json: @website.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /websites/1
  # PATCH/PUT /websites/1.json
  def update
    result = nil
    respond_to do |format|
      result = Distillator::RolloutTransition.call(
        website: @website,
        to_mode: website_params[:distillator_mode],
        actor: rollout_actor,
        reason: params[:reason],
        attributes: website_params.to_h
      )

      if result.success?
        flash_notice = ["Website was successfully updated."]
        flash_notice << "Warnings: #{result.warnings.join(', ')}" if result.warnings.any?
        format.html { redirect_to @website, notice: flash_notice.join(" ") }
        format.json { render :show, status: :ok, location: @website }
      else
        flash.now[:alert] = result.errors.join(", ") if result.errors.any?
        format.html { render :edit }
        format.json { render json: @website.errors, status: :unprocessable_entity }
      end
    end
  end

  def activate_after_review
    result = Distillator::RolloutTransition.call(
      website: @website,
      to_mode: "active",
      actor: rollout_actor,
      reason: params[:reason],
      review: true
    )

    if result.success?
      redirect_to @website, notice: "Website activated after review. Reason recorded."
    else
      redirect_to @website, alert: result.errors.join(", ")
    end
  end

  def activate_anyway
    result = Distillator::RolloutTransition.call(
      website: @website,
      to_mode: "active",
      actor: rollout_actor,
      reason: params[:reason],
      override: true
    )

    if result.success?
      redirect_to @website, notice: "Website activated. Override recorded."
    else
      redirect_to @website, alert: result.errors.join(", ")
    end
  end

  def confirm_cutover
    if @website.distillator_mode != "active"
      return redirect_to website_path(@website, anchor: "active-operation"), status: :see_other,
        alert: "This website must be Active before you can confirm migration."
    end

    @website.with_lock do
      validation = website_validation_summary
      if validation.cutover
        redirect_to website_path(@website, anchor: "active-operation"), status: :see_other, notice: "Migration is already recorded."
      elsif validation.confirmable_cutover?
        fields = params.permit(:completed_at, :operator, :evidence)
        Distillator::VerifiedCutover.confirm!(website: @website,
          completed_at: Time.zone.iso8601(fields[:completed_at].to_s), actor: fields[:operator].to_s.strip,
          evidence: fields[:evidence].to_s.strip)
        redirect_to website_path(@website, anchor: "active-operation"), status: :see_other, notice: "Migration confirmed."
      else
        redirect_to website_path(@website, anchor: "active-operation"), status: :see_other,
          alert: "A passing Thorough check is required before you can confirm migration."
      end
    end
  rescue ArgumentError => error
    message = error.message == "invalid date" ? "Enter the date and time of the Artsdata handoff." : error.message
    redirect_to website_path(@website, anchor: "active-operation"), status: :see_other, alert: message
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
    params.require(:website).permit(:name, :seedurl, :graph_name, :default_language, :schedule_every_days, :schedule_time, :last_refresh, :distillator_mode, :monitorable)
  end

  def configure_dashboard
    default = cookies.signed[:website_default_dashboard].presence_in(DASHBOARDS) || "information"
    @dashboard = @filters[:dashboard].presence_in(DASHBOARDS) || default
    @filters[:dashboard] = @dashboard if @filters.key?(:dashboard) || default == "action"
    @filters.delete(:metrics) unless @filters[:metrics] == "full"
    @filters.delete(:action_filter) unless Distillator::WebsiteActionSummary::FILTERS.key?(@filters[:action_filter])
    @dashboard_selection_id = @filters[:transition_website_id].to_i if !@filters[:retry_transition_batch_id] &&
      @filters[:transition_website_id].to_s.match?(/\A[1-9][0-9]{0,17}\z/)
    @filters.delete(:transition_website_id) unless @dashboard_selection_id
  end

  def prepare_action_dashboard
    @dashboard_actions = Distillator::WebsiteActionSummary.for_websites(@websites.to_a,
      inventories: @inventory_freshness, validations: @validation_summaries, eligible_ids: @transition_eligible_ids,
      running: @dashboard_running)
    @action_filter = @filters[:action_filter] unless @retry_transition_batch || @dashboard_selection_id
    @action_filter ||= "all"
    @primary_actions = @dashboard_actions.transform_values do |actions|
      match = actions.find { |action| action.matches?(@action_filter) }
      actions.first.takes_precedence? ? actions.first : match if match
    end
    @websites = @websites.select { |site| @primary_actions[site.id] } if @action_filter != "all"
    @transition_eligible_ids &= @websites.map(&:id)
    # The existing explicit table sort breaks ties within a priority.
    @action_rows = @websites.each_with_index.sort_by { |site, index| [@primary_actions[site.id]&.rank || 5, index] }.map(&:first)
    @action_groups = @action_rows.group_by do |site|
      priority = @primary_actions[site.id]&.priority
      priority.in?(%i[p0 p1]) ? :intervention : priority || :"no-action"
    end
  end

  def sort_column
    allowed_columns = %w[
      name seedurl default_language schedule_every_days
      schedule_time last_refresh graph_name
      webpages_count event_pages_count publishable_event_percentage statements_count refreshed_24h updated_24h
    ]
    normalized_sort_param(params[:sort], allowed: allowed_columns, default: "name")
  end

  def sort_direction
    normalized_direction_param(params[:direction], default: "asc")
  end

  def computed_sort?
    %w[webpages_count event_pages_count publishable_event_percentage statements_count refreshed_24h updated_24h].include?(sort_column)
  end

  def sort_in_memory(relation)
    direction = sort_direction == "desc" ? -1 : 1
    column = sort_column

    relation.to_a.sort_by do |website|
      pages = @webpage_summaries.fetch(website.id) { Distillator::WebsiteWebpageSummary.empty_summary }
      value =
        case column
        when "webpages_count"
          pages[:total]
        when "event_pages_count"
          pages[:by_class].fetch("Event")
        when "publishable_event_percentage"
          pages[:publishable_event_resource_percentage]
        when "statements_count"
          @statements_grouped[website.seedurl] || 0
        when "refreshed_24h"
          @statements_refreshed_24hr[website.seedurl] || 0
        when "updated_24h"
          @statements_updated_24hr[website.seedurl] || 0
        else
          0
        end

      value.nil? ? [1, 0, website.id] : [0, direction * value, website.id]
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

  def website_validation_summary
    inventories = Distillator::WebsiteInventoryFreshness.for_websites([@website.id])
    Distillator::WebsiteValidationHistory.for_websites([@website], inventories: inventories).fetch(@website.id)
  end

  def rollout_actor
    request.remote_ip.presence || "unknown"
  end
end
