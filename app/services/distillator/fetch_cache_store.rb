require "cgi"
require "nokogiri"

module Distillator
  class FetchCacheStore
    # See docs/rollout_modes.md for the shared rollout glossary and operator copy.
    # FetchCacheStore owns Wringer-compatible cache lookup and refresh semantics
    # while FetchService performs a single legacy, shadow, internal, or replay fetch.
    DEFAULT_SIGNALS = {
      "network_status" => "ok",
      "content_type" => "unknown",
      "redirect_type" => "none"
    }.freeze

    Result = Struct.new(
      :status,
      :body,
      :html,
      :headers,
      :final_url,
      :redirect_chain,
      :http_response_code,
      :signals,
      :hints,
      :duration_ms,
      :cache_hit,
      :cache_write,
      :cache_reason,
      :uri_key,
      :normalized_url,
      :fetch_path,
      :name,
      :scrape_date,
      :successful_refresh,
      :cache,
      keyword_init: true
    ) do
      def [](key)
        public_send(key)
      end

      def transport_success?
        Distillator::BooleanParam.parse(signal_value("transport_success"))
      end

      def content_success?
        Distillator::BooleanParam.parse(signal_value("content_success"))
      end

      def blocking_issue?
        !content_success? && blocking_issue_key.present?
      end

      def blocking_issue_key
        signal_value("blocking_issue_key").presence || signal_value("primary_issue_key").presence
      end

      def retry_policy
        signal_value("retry")
      end

      def cache_policy
        signal_value("cache")
      end

      def to_h
        members.index_with { |member| public_send(member) }
      end

      private

      def signal_value(key)
        (signals || {}).to_h[key.to_s] || (signals || {}).to_h[key.to_sym]
      end
    end

    def self.fetch(**kwargs)
      new(**kwargs).fetch
    end

    def self.lookup_by_term(term)
      cache = Distillator::FetchCache.find_by(uri_key: term.to_s) ||
              Distillator::FetchCache.find_by(uri_key: CGI.escape(term.to_s))
      return [] unless cache

      [{
        id: cache.id,
        uri: cache.uri_key,
        html: cache.html,
        name: cache.name,
        json_ld: cache.json_ld,
        scrape_date: cache.scrape_date,
        successful_refresh: cache.successful_refresh,
        http_response_code: cache.http_response_code,
        created_at: cache.created_at,
        updated_at: cache.updated_at
      }]
    end

    def self.refresh_decision(cache:, force_scrape:, force_scrape_every_hrs:, clock: Time.zone)
      return { refresh: true, reason: :missing_cache } unless cache
      return { refresh: true, reason: :force_scrape } if truthy?(force_scrape)
      return { refresh: true, reason: :missing_scrape_date } if cache.scrape_date.nil?
      return { refresh: false, reason: :fresh_cache } if force_scrape_every_hrs.blank?

      threshold_hours = force_scrape_every_hrs.to_i
      refresh = cache.scrape_date < clock.now - threshold_hours.hours
      reason = refresh ? :stale_by_force_scrape_every_hrs : :fresh_cache

      { refresh: refresh, reason: reason }
    end

    def self.truthy?(value)
      Distillator::BooleanParam.parse(value)
    end

    def initialize(
      uri:,
      include_fragment: false,
      force_scrape: false,
      force_scrape_every_hrs: nil,
      render_js: false,
      use_phantomjs: nil,
      json_post: false,
      absolute_src: false,
      mode: nil,
      website: nil,
      website_id: nil,
      client: nil,
      agent: nil,
      use_wringer: nil,
      safe_wringer_call: nil,
      logger: Rails.logger,
      clock: Time.zone,
      log_context: {}
    )
      @uri = uri
      @include_fragment = self.class.truthy?(include_fragment)
      @force_scrape = self.class.truthy?(force_scrape)
      @force_scrape_every_hrs = force_scrape_every_hrs
      @render_js = self.class.truthy?(render_js)
      @use_phantomjs = self.class.truthy?(use_phantomjs)
      @json_post = self.class.truthy?(json_post)
      @absolute_src = self.class.truthy?(absolute_src)
      @mode = mode
      @website = website
      @website_id = website_id
      @client = client
      @agent = agent
      @use_wringer = use_wringer
      @safe_wringer_call = safe_wringer_call
      @logger = logger
      @clock = clock
      @log_context = (log_context || {}).to_h
    end

    def fetch
      key = Distillator::WringerUrlKey.call(uri, include_fragment: include_fragment)
      cache = Distillator::FetchCache.find_by(uri_key: key.uri_key)
      decision = self.class.refresh_decision(
        cache: cache,
        force_scrape: force_scrape,
        force_scrape_every_hrs: force_scrape_every_hrs,
        clock: clock
      )

      unless decision[:refresh]
        result = build_result(cache, key, cache_hit: true, cache_write: false, cache_reason: decision[:reason], fetch_path: "cache")
        log_cache_event("cache.hit", key: key, result: result)
        return result
      end

      had_cache = cache.present?
      log_cache_event(had_cache ? "cache.refresh" : "cache.miss", key: key, cache_reason: decision[:reason].to_s)

      cache ||= Distillator::FetchCache.new(uri_key: key.uri_key)
      cache.normalized_url ||= key.normalized_url

      fetch_result = Distillator::FetchService.fetch_result(
        url: key.normalized_url,
        render_js: rendered_fetch_for_key?(key),
        scrape_options: scrape_options(key),
        mode: mode.presence,
        website: website,
        website_id: website_id,
        client: client,
        agent: agent,
        use_wringer: use_wringer,
        safe_wringer_call: safe_wringer_call,
        logger: logger,
        log_context: log_context
      )

      write_fetch_result(cache, key, fetch_result)

      build_result(
        cache,
        key,
        fetch_result: fetch_result,
        cache_hit: false,
        cache_write: true,
        cache_reason: decision[:reason],
        fetch_path: fetch_result[:fetch_path]
      ).tap do |result|
        log_cache_event(had_cache ? "cache.refresh" : "cache.miss", key: key, result: result)
      end
    end

    private

    attr_reader(
      :uri,
      :include_fragment,
      :force_scrape,
      :force_scrape_every_hrs,
      :render_js,
      :use_phantomjs,
      :json_post,
      :absolute_src,
      :mode,
      :website,
      :website_id,
      :client,
      :agent,
      :use_wringer,
      :safe_wringer_call,
      :logger,
      :clock,
      :log_context
    )

    def build_result(cache, key, fetch_result: nil, cache_hit:, cache_write:, cache_reason:, fetch_path:)
      body = cache&.body.presence || cache&.html
      response_status =
        if body.present?
          :ok
        else
          fetch_result&.dig(:status) || :abort
        end

      response_body =
        if body.present?
          body
        else
          fetch_result&.dig(:body)
        end

      Result.new(
        status: response_status,
        body: response_body,
        html: cache&.html,
        headers: (cache&.headers || {}).to_h,
        final_url: cache&.final_url,
        redirect_chain: Array(cache&.redirect_chain),
        http_response_code: cache&.http_response_code,
        signals: (cache&.signals || {}).to_h,
        hints: Array(cache&.hints),
        duration_ms: fetch_result&.dig(:duration_ms) || 0,
        cache_hit: cache_hit,
        cache_write: cache_write,
        cache_reason: cache_reason.to_s,
        uri_key: key.uri_key,
        normalized_url: key.normalized_url,
        fetch_path: fetch_path,
        name: cache&.name,
        scrape_date: cache&.scrape_date,
        successful_refresh: cache&.successful_refresh,
        cache: cache
      )
    end

    def write_fetch_result(cache, key, fetch_result)
      raw_body = raw_body_for(fetch_result)
      http_code = fetch_result[:http_code] || Distillator::FetchService.default_http_code_for(fetch_result)
      final_url = fetch_result[:final_url].presence || key.normalized_url
      headers = Distillator::FetchService.normalize_headers(fetch_result[:headers] || {})
      signals = normalize_signals(fetch_result, key: key, headers: headers, body: raw_body, final_url: final_url)
      hints = normalize_hints(fetch_result, signals: signals, body: raw_body)

      cache.assign_attributes(
        normalized_url: key.normalized_url,
        scrape_date: now,
        name: extract_title(raw_body) || cache.name,
        http_response_code: http_code,
        headers: headers,
        signals: signals,
        hints: hints,
        final_url: fetch_result[:final_url],
        redirect_chain: Array(fetch_result[:redirect_chain])
      )

      if preserve_last_good_failure?(cache, http_code: http_code, raw_body: raw_body)
        cache.signals = (cache.signals || {}).to_h.merge("last_good_preserved_failure" => true)
        cache.hints = (Array(cache.hints) + ["last_good_preserved_failure"]).uniq
      end

      cache.signals = annotate_storage_signals(cache.signals, cache: cache, abort_update: abort_update_policy?(fetch_result))

      return cache.save! if abort_update_policy?(fetch_result)
      return cache.save! unless content_successful_fetch?(signals: cache.signals || {}, http_code: http_code, raw_body: raw_body)

      html = escape_erb_tokens(raw_body.to_s)
      html = Distillator::HtmlAbsolutizer.call(html: html, base_url: final_url) if self.class.truthy?(absolute_src)
      cache.assign_attributes(
        html: html,
        body: html,
        successful_refresh: now
      )
      cache.save!
    end

    def scrape_options(key)
      rendered_fetch = rendered_fetch_for_key?(key)

      {
        uri_key: key.uri_key,
        include_fragment: include_fragment,
        force_scrape: force_scrape,
        force_scrape_every_hrs: force_scrape_every_hrs,
        json_post: json_post,
        absolute_src: absolute_src,
        use_phantomjs: rendered_fetch,
        render_js: rendered_fetch,
        iframe: iframe_key?(key)
      }
    end

    def render_js?
      self.class.truthy?(render_js) || self.class.truthy?(use_phantomjs)
    end

    def iframe_key?(key)
      key.uri_key.to_s.end_with?("iframe")
    end

    def rendered_fetch_for_key?(key)
      render_js? || iframe_key?(key)
    end

    def raw_body_for(fetch_result)
      raw_body = fetch_result[:raw_body]
      return raw_body if raw_body.is_a?(String)

      body = fetch_result[:body]
      body.is_a?(String) ? body : nil
    end

    def normalize_signals(fetch_result, key:, headers:, body:, final_url:)
      wringer_signals = fetch_result.dig(:wringer, :signals)
      base = DEFAULT_SIGNALS.merge(redirected_signals(original_url: key.normalized_url, final_url: final_url))
      content_type = detect_content_type(headers, body)
      fetched_body_bytes = body.is_a?(String) ? body.bytesize : nil
      if wringer_signals.is_a?(Hash) && wringer_signals.present?
        signals = base.merge(wringer_signals.stringify_keys).merge("fetch_path" => fetch_result[:fetch_path].to_s)
        propagate_wringer_policy_signals!(signals, fetch_result)
        signals["content_type"] = content_type if signals["content_type"].blank?
        signals["json_detected"] = true if content_type == "json"
        signals["fetched_body_bytes"] = fetched_body_bytes unless fetched_body_bytes.nil?
        signals["fetched_body_state"] = fetched_body_state_for(body)
        signals["empty_body"] = true if actual_empty_body_response?(signals: signals, body: body)
        clear_empty_body_signal!(signals) if policy_aborted_non_empty_response?(signals: signals, http_code: http_code_for(fetch_result), body: body)
        annotate_policy_rejection_signals!(signals, http_code: http_code_for(fetch_result), body: body)
        signals["fetch_backend"] ||= fetch_backend_for(fetch_result, key: key)
        signals["request_method"] ||= request_method_for
        signals["use_phantomjs"] = use_phantomjs_for(key) if signals["use_phantomjs"].nil?
        signals["phantomjs_iframe_extraction"] = phantomjs_iframe_extraction_for(key) if signals["phantomjs_iframe_extraction"].nil?
        signals["transport_success"] = transport_success_for(fetch_result) if signals["transport_success"].nil?
        signals["content_success"] = infer_content_success(signals: signals, http_code: http_code_for(fetch_result), raw_body: body) if signals["content_success"].nil?
        return signals
      end

      signals = base.merge(
        "content_type" => content_type,
        "fetch_path" => fetch_result[:fetch_path].to_s,
        "fetch_backend" => fetch_backend_for(fetch_result, key: key),
        "request_method" => request_method_for,
        "use_phantomjs" => use_phantomjs_for(key),
        "phantomjs_iframe_extraction" => phantomjs_iframe_extraction_for(key)
      )
      propagate_wringer_policy_signals!(signals, fetch_result)
      signals["json_detected"] = true if content_type == "json"
      signals["fetched_body_bytes"] = fetched_body_bytes unless fetched_body_bytes.nil?
      signals["fetched_body_state"] = fetched_body_state_for(body)
      signals["empty_body"] = true if actual_empty_body_response?(signals: signals, body: body)
      clear_empty_body_signal!(signals) if policy_aborted_non_empty_response?(signals: signals, http_code: http_code_for(fetch_result), body: body)
      annotate_policy_rejection_signals!(signals, http_code: http_code_for(fetch_result), body: body)
      signals["transport_success"] = transport_success_for(fetch_result)
      signals["content_success"] = infer_content_success(signals: signals, http_code: http_code_for(fetch_result), raw_body: body)
      signals
    end

    def normalize_hints(fetch_result, signals:, body:)
      wringer_hints = fetch_result.dig(:wringer, :hints)
      if wringer_hints.present?
        hints = Array(wringer_hints).map(&:to_s)
        hints.delete("empty_body") if policy_aborted_non_empty_response?(signals: signals, http_code: http_code_for(fetch_result), body: body)
        return hints.uniq
      end

      hints = []
      hints << "json_detected" if signals["json_detected"]
      hints << "empty_body" if actual_empty_body_response?(signals: signals, body: body)
      hints.uniq
    end

    def redirected_signals(original_url:, final_url:)
      redirected = final_url.present? && final_url != original_url
      {
        "redirect_type" => redirected ? "normal" : "none",
        "redirected" => redirected,
        "final_url" => final_url
      }
    end

    def detect_content_type(headers, body)
      content_type = (headers[:content_type] || headers["content_type"] || headers["Content-Type"]).to_s.downcase
      return "json" if content_type.include?("json") || body.to_s.lstrip.start_with?("{", "[")
      return "html" if content_type.include?("html") || body.to_s.downcase.include?("<html")

      "unknown"
    end

    def extract_title(html)
      return nil if html.blank?

      Nokogiri::HTML(html.to_s).title
    rescue StandardError
      nil
    end

    def successful_http?(code)
      code.to_i.to_s.start_with?("2")
    end

    def content_successful_fetch?(signals:, http_code:, raw_body:)
      explicit = signals.to_h["content_success"]
      return Distillator::BooleanParam.parse(explicit) unless explicit.nil?

      infer_content_success(signals: signals, http_code: http_code, raw_body: raw_body)
    end

    def infer_content_success(signals:, http_code:, raw_body:)
      return false if policy_action_for(signals).to_s == "abort_update"
      return false if signals.to_h["transport_success"] == false || signals.to_h["transport_success"].to_s == "false"

      successful_http?(http_code) && usable_body?(raw_body)
    end

    def usable_body?(body)
      body.is_a?(String) && body.present?
    end

    def escape_erb_tokens(html)
      html.to_s.gsub("<%", "<&percnt;").gsub("%>", "&percnt;>")
    end

    def fetch_backend_for(fetch_result, key:)
      case fetch_result[:fetch_path].to_s
      when "blocked"
        "blocked"
      when "legacy"
        "legacy"
      when "native"
        rendered_fetch_for_key?(key) ? "phantomjs" : "native"
      else
        "native"
      end
    end

    def request_method_for
      json_post ? "POST" : "GET"
    end

    def abort_update_policy?(fetch_result)
      action = fetch_result.dig(:wringer, :policy_action)
      action = fetch_result.dig(:wringer, :policy, :action) if action.blank?
      action = fetch_result.dig(:wringer, :policy, "action") if action.blank?
      action.to_s == "abort_update"
    end

    def preserve_last_good_failure?(cache, http_code:, raw_body:)
      cache.html.present? && !content_successful_fetch?(signals: cache.signals || {}, http_code: http_code, raw_body: raw_body)
    end

    def propagate_wringer_policy_signals!(signals, fetch_result)
      signals["policy_action"] ||= fetch_result.dig(:wringer, :policy_action).presence

      retry_value = fetch_result.dig(:wringer, :retry)
      signals["retry"] = retry_value unless retry_value.nil? || signals.key?("retry")

      cache_value = fetch_result.dig(:wringer, :cache)
      signals["cache"] = cache_value unless cache_value.nil? || signals.key?("cache")
    end

    def policy_action_for(signals)
      signals.to_h["policy_action"] || signals.to_h[:policy_action]
    end

    def fetched_body_state_for(body)
      return "unknown" unless body.is_a?(String)
      return "empty" if body.strip.empty?

      "non_empty"
    end

    def actual_empty_body_response?(signals:, body:)
      return false if policy_aborted_non_empty_response?(signals: signals, http_code: nil, body: body)

      body.is_a?(String) && body.strip.empty?
    end

    def policy_aborted_non_empty_response?(signals:, http_code:, body:)
      policy_action_for(signals).to_s == "abort_update" &&
        successful_http?(http_code || signals.to_h["http_response_code"]) &&
        signals.to_h["content_type"].to_s == "html" &&
        body.is_a?(String) &&
        body.present?
    end

    def clear_empty_body_signal!(signals)
      signals.delete("empty_body")
      signals.delete(:empty_body)
    end

    def annotate_policy_rejection_signals!(signals, http_code:, body:)
      return unless policy_aborted_non_empty_response?(signals: signals, http_code: http_code, body: body)

      signals["content_rejected"] = true
      signals["storage_decision"] ||= "abort_update"
      signals["stored_body_state"] ||= "not_stored"
      signals["cache_body_empty_after_abort"] = true
    end

    def annotate_storage_signals(signals, cache:, abort_update:)
      values = (signals || {}).to_h.stringify_keys
      values["stored_body_bytes"] = cache.body.to_s.bytesize
      values["storage_decision"] ||= abort_update ? "abort_update" : "stored"
      if abort_update
        values["stored_body_state"] =
          if cache.body.present?
            values["last_good_preserved_failure"] == true || values["last_good_preserved_failure"].to_s == "true" ? "preserved_last_good" : "stored"
          else
            "not_stored"
          end
      else
        values["stored_body_state"] ||= cache.body.present? ? "stored" : "empty"
      end
      values
    end

    def http_code_for(fetch_result)
      fetch_result[:http_code] || Distillator::FetchService.default_http_code_for(fetch_result)
    end

    def transport_success_for(fetch_result)
      fetch_result[:status] == :ok && successful_http?(http_code_for(fetch_result))
    end

    def use_phantomjs_for(key)
      rendered_fetch_for_key?(key)
    end

    def phantomjs_iframe_extraction_for(key)
      rendered_fetch_for_key?(key) && iframe_key?(key)
    end

    def now
      clock.now
    end

    def log_cache_event(event, key:, result: nil, cache_reason: nil)
      payload = {
        service: "distillator",
        event: event,
        uri: key.normalized_url,
        uri_key: key.uri_key,
        mode: mode.to_s,
        fetch_path: result&.fetch_path,
        cache_reason: cache_reason || result&.cache_reason,
        http_response_code: result&.http_response_code,
        network_status: result&.signals&.[]("network_status"),
        content_type: result&.signals&.[]("content_type"),
        redirect_type: result&.signals&.[]("redirect_type"),
        duration_ms: result&.duration_ms,
        statement_id: log_context[:statement_id],
        source_id: log_context[:source_id],
        webpage_id: log_context[:webpage_id],
        website_id: log_context[:website_id]
      }
      logger.info(payload)
    end
  end
end
