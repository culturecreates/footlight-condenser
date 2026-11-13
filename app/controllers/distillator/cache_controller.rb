module Distillator
  class CacheController < ApplicationController
    include SortableIndex

    DEFAULT_PER_PAGE = 50
    MAX_PER_PAGE = 100
    SORT_COLUMNS = {
      "id" => :id,
      "updated_at" => :updated_at,
      "scrape_date" => :scrape_date,
      "successful_refresh" => :successful_refresh,
      "http_response_code" => :http_response_code,
      "name" => :name,
      "normalized_url" => :normalized_url,
      "uri_key" => :uri_key,
      "html_bytes" => :html_bytes,
      "body_bytes" => :body_bytes
    }.freeze
    SORT_DIRECTIONS = %w[asc desc].freeze

    before_action :set_cache, only: [:show, :raw, :wring_json, :raw_view, :wring_json_view]

    def index
      @filters = current_filters
      @sort = current_sort
      @direction = current_direction
      @view_mode = current_view
      @last_action_result = flash[:last_action_result]
      @preserved_index_params = canonical_index_params
      if request.format.html? && canonical_redirect_required?
        return redirect_to distillator_cache_index_path(canonical_index_params)
      end

      query = Distillator::CacheIndexQuery.call(
        filters: @filters,
        sort: @sort,
        direction: @direction,
        page: page,
        per_page: per_page
      )
      @summary_cards = Distillator::CacheSummary.call(scope: query.summary_scope) if query.summary_scope.is_a?(ActiveRecord::Relation)
      @summary_cards ||= Distillator::CacheSummary.call(caches: query.summary_scope)
      @pagination = {
        page: query.page,
        per_page: query.per_page,
        total_count: query.total_count,
        total_pages: query.total_pages
      }
      @caches = query.records.map { |cache| serialize(cache).merge(html_preview: html_preview_for(cache)) }

      respond_to do |format|
        format.html
        format.json do
          apply_pagination_headers
          render json: @caches
        end
      end
    end

    def compare
      @comparison = Distillator::CacheCompare.call(
        uri: params[:uri],
        include_fragment: params[:include_fragment],
        comparison_policy: params[:comparison_policy]
      )
    rescue StandardError
      @comparison = {
        uri: params[:uri],
        uri_key: nil,
        legacy_cache: nil,
        legacy_source: "unavailable",
        legacy_lookup_error: "Unexpected comparison failure",
        condenser_cache: nil,
        condenser_source: "local_fetch_cache",
        distillator_cache: nil,
        distillator_source: "local_fetch_cache",
        diffs: {},
        missing: { legacy: true, condenser: true, distillator: true }
      }
      response.status = :unprocessable_entity
    end

    def show
      return head :not_found unless @cache

      @cache_payload = serialize(@cache)
      @last_action_result = flash[:last_action_result]
      @preview = preview_payload(**default_preview_params) if preview_requested?

      respond_to do |format|
        format.html
        format.json { render json: @preview.present? ? @cache_payload.merge(preview: @preview) : @cache_payload }
      end
    end

    def raw
      return head :not_found unless @cache

      apply_raw_html_safety_headers
      response.headers.delete "X-Frame-Options"
      render html: (@cache.html || "").html_safe, layout: false
    end

    def wring_json
      return head :not_found unless @cache

      response.headers.delete "X-Frame-Options"
      render json: {
        html: @cache.html,
        signals: @cache.signals || {},
        hints: @cache.hints || [],
        final_url: @cache.final_url,
        redirect_chain: @cache.redirect_chain || [],
        http_code: @cache.http_response_code
      }
    end

    def raw_view
      return head :not_found unless @cache

      @cache_payload = serialize(@cache)
    end

    def wring_json_view
      return head :not_found unless @cache

      @wring_payload = wring_payload(@cache)
      @cache_payload = serialize(@cache)
    end

    def preview
      @preview = preview_payload(
        uri: params[:uri],
        include_fragment: params[:include_fragment],
        force_scrape: params[:force_scrape],
        force_scrape_every_hrs: params[:force_scrape_every_hrs],
        fetch_kind: params[:fetch_kind]
      )

      respond_to do |format|
        format.html
        format.json { render json: @preview }
      end
    end

    def fetch
      return fetch_ui_disabled unless refresh_ui_enabled?

      result = Distillator::CacheFetchCommand.new(params: fetch_command_params).call

      if result.ok?
        fetch_result = result.fetch_result
        redirect_to(
          distillator_cache_index_path(preserved_index_params),
          notice: success_flash_message(result),
          flash: { last_action_result: last_action_result_payload(fetch_result, result.message) }
        )
      else
        redirect_to(
          distillator_cache_index_path(preserved_index_params),
          alert: failure_flash_message(result.errors)
        )
      end
    end

    private

    def set_cache
      @cache = Distillator::FetchCache.find_by(id: params[:id])
    end

    def serialize(cache)
      Distillator::FetchCacheCompatSerializer.new(cache).as_json
    end

    def wring_payload(cache)
      {
        html: cache.html,
        signals: cache.signals || {},
        hints: cache.hints || [],
        final_url: cache.final_url,
        redirect_chain: cache.redirect_chain || [],
        http_code: cache.http_response_code
      }
    end

    def apply_raw_html_safety_headers
      response.set_header(
        "Content-Security-Policy",
        "default-src 'none'; img-src data: http: https:; media-src data: http: https:; style-src 'unsafe-inline' http: https:; font-src data: http: https:; sandbox"
      )
      response.set_header("X-Content-Type-Options", "nosniff")
      response.content_type = "text/html"
    end

    def preview_payload(uri:, include_fragment:, force_scrape:, force_scrape_every_hrs:, fetch_kind: "normal")
      Distillator::CacheRefreshPreview.call(
        uri: uri,
        include_fragment: include_fragment,
        force_scrape: force_scrape,
        force_scrape_every_hrs: force_scrape_every_hrs,
        fetch_kind: fetch_kind
      )
    end

    def preview_requested?
      params[:preview].to_s == "true"
    end

    def refresh_ui_enabled?
      ENV["DISTILLATOR_CACHE_REFRESH_UI"] == "true"
    end
    helper_method :refresh_ui_enabled?

    def default_preview_params
      {
        uri: @cache.normalized_url,
        include_fragment: params[:include_fragment],
        force_scrape: params[:force_scrape],
        force_scrape_every_hrs: params[:force_scrape_every_hrs],
        fetch_kind: params[:fetch_kind] || "normal"
      }
    end

    def current_filters
      {
        term: params[:term].to_s.strip,
        http_response_code: params[:http_response_code].to_s.strip,
        has_html: params[:has_html].to_s,
        network_status: params[:network_status].to_s.strip,
        health: params[:health].to_s,
        status_group: params[:status_group].to_s,
        content_type: params[:content_type].to_s,
        hint: params[:hint].to_s.strip,
        redirected: params[:redirected].to_s,
        last_attempt: params[:last_attempt].to_s,
        last_success: params[:last_success].to_s
      }
    end

    def apply_pagination_headers
      response.headers["X-Page"] = @pagination[:page].to_s
      response.headers["X-Per-Page"] = @pagination[:per_page].to_s
      response.headers["X-Total-Count"] = @pagination[:total_count].to_s
      response.headers["X-Total-Pages"] = @pagination[:total_pages].to_s
    end

    def page
      value = params[:page].to_i
      value.positive? ? value : 1
    end

    def per_page
      value = params[:per_page].to_i
      value = DEFAULT_PER_PAGE unless value.positive?
      [value, MAX_PER_PAGE].min
    end

    def current_sort
      normalized_sort_param(params[:sort], allowed: SORT_COLUMNS.keys, default: "updated_at")
    end

    def current_direction
      normalized_direction_param(params[:direction], default: "desc")
    end

    def canonical_redirect_required?
      request.query_parameters != canonical_index_params.transform_values(&:to_s).stringify_keys
    end

    def canonical_index_params
      canonical = {}
      canonical[:term] = @filters[:term] if @filters[:term].present?
      canonical[:http_response_code] = @filters[:http_response_code] if @filters[:http_response_code].match?(/\A\d+\z/)
      canonical[:has_html] = @filters[:has_html] if %w[true false].include?(@filters[:has_html])
      canonical[:network_status] = @filters[:network_status] if @filters[:network_status].present?
      canonical[:health] = @filters[:health] if @filters[:health].present?
      canonical[:status_group] = @filters[:status_group] if @filters[:status_group].present?
      canonical[:content_type] = @filters[:content_type] if @filters[:content_type].present?
      canonical[:hint] = @filters[:hint] if @filters[:hint].present?
      canonical[:redirected] = @filters[:redirected] if %w[true false].include?(@filters[:redirected])
      canonical[:last_attempt] = @filters[:last_attempt] if @filters[:last_attempt].present?
      canonical[:last_success] = @filters[:last_success] if @filters[:last_success].present?
      canonical[:sort] = @sort if @sort != "updated_at"
      canonical[:direction] = @direction if @direction != "desc"
      canonical[:view] = @view_mode if @view_mode == "parity"
      canonical[:page] = page if page > 1
      canonical[:per_page] = per_page if per_page != DEFAULT_PER_PAGE
      canonical
    end

    def preserved_index_params
      params.permit(
        :term,
        :http_response_code,
        :health,
        :status_group,
        :has_html,
        :content_type,
        :network_status,
        :redirected,
        :hint,
        :last_attempt,
        :last_success,
        :sort,
        :direction,
        :view,
        :page,
        :per_page
      ).to_h.compact_blank
    end

    def fetch_command_params
      params.permit(
        :uri,
        :fetch_kind,
        :include_fragment,
        :force_scrape,
        :force_scrape_every_hrs,
        :json_post,
        :absolute_src
      )
    end

    def html_preview_for(cache)
      cache.html.to_s.first(160)
    end

    def current_view
      view = params[:view].to_s
      Distillator::CacheHelper::VIEW_MODES.include?(view) ? view : "rich"
    end

    def success_flash_message(result)
      fetch_result = result.fetch_result
      parts = ["Fetched #{fetch_kind_label(result.message)} for #{fetch_result&.normalized_url || fetch_command_params[:uri]}"]
      parts << "HTTP #{fetch_result.http_response_code}" if fetch_result&.http_response_code.present?
      parts << "path #{fetch_result.fetch_path}" if fetch_result&.fetch_path.present?
      parts << cache_reason_phrase(fetch_result&.cache_reason) if fetch_result&.cache_reason.present?
      parts << html_result_phrase(fetch_result)
      parts.compact.join(" — ")
    end

    def failure_flash_message(errors)
      "#{fetch_kind_label(fetch_command_params[:fetch_kind])} for #{fetch_command_params[:uri].presence || 'blank URI'} failed: #{errors.join(', ')}. No fetch performed."
    end

    def fetch_kind_label(fetch_kind)
      helpers.cache_fetch_kind_label(fetch_kind)
    end

    def cache_reason_phrase(cache_reason)
      case cache_reason.to_s
      when "force_scrape"
        "cache refresh forced"
      when "missing_cache"
        "cache miss"
      when "missing_scrape_date"
        "missing scrape date"
      when "stale_by_force_scrape_every_hrs"
        "refresh needed by age threshold"
      else
        "cache reason #{cache_reason}"
      end
    end

    def html_result_phrase(fetch_result)
      return nil unless fetch_result

      fetch_result.html.present? ? "HTML written" : "HTML missing"
    end

    def last_action_result_payload(fetch_result, fetch_kind)
      return {} unless fetch_result

      {
        "fetch_kind_label" => fetch_kind_label(fetch_kind),
        "normalized_url" => fetch_result.normalized_url,
        "http_response_code" => fetch_result.http_response_code,
        "cache_reason" => fetch_result.cache_reason,
        "fetch_path" => fetch_result.fetch_path,
        "html_state" => html_result_phrase(fetch_result)
      }
    end

    def fetch_ui_disabled
      redirect_to distillator_cache_index_path(preserved_index_params), alert: "Cache inspection mode. Refresh actions are not available in this environment."
    end
  end
end
