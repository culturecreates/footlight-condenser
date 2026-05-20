module Distillator
  class FetchService
    # FetchService decides which single fetch path to execute.
    # Wringer-compatible cache refresh semantics belong in FetchCacheStore.
    def self.fetch(
      url:,
      render_js: false,
      scrape_options: {},
      mode: nil,
      website: nil,
      website_id: nil,
      client: nil,
      agent: nil,
      use_wringer: nil,
      safe_wringer_call: nil,
      logger: nil,
      log_context: {}
    )
      result = fetch_result(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        mode: mode,
        website: website,
        website_id: website_id,
        client: client,
        agent: agent,
        use_wringer: use_wringer,
        safe_wringer_call: safe_wringer_call,
        logger: logger,
        log_context: log_context
      )
      response = response_contract(result, result[:duration_ms])
      Distillator::FetchRecorder.record(url: url, response: response)
      response
    end

    def self.fetch_result(
      url:,
      render_js: false,
      scrape_options: {},
      mode: nil,
      website: nil,
      website_id: nil,
      client: nil,
      agent: nil,
      use_wringer: nil,
      safe_wringer_call: nil,
      logger: nil,
      log_context: {}
    )
      scrape_options, log_context = sanitize_scrape_options(scrape_options, log_context)

      if ENV["REPLAY_FETCH"].present?
        replay = Distillator::FetchReplay.load(url: url)
        result = {
          status: replay[:status],
          body: replay[:body],
          headers: replay[:headers] || {},
          final_url: replay[:final_url],
          redirect_chain: replay[:redirect_chain] || [],
          wringer: replay[:wringer] || {},
          duration_ms: replay[:duration_ms] || 0,
          http_code: replay.dig(:wringer, :http_code) || default_http_code_for(replay),
          raw_body: replay[:body],
          fetch_path: "replay"
        }
        log_fetch_outcome(logger, mode: :replay, mode_source: :replay, url: url, result: result, log_context: log_context)
        return result
      end

      mode_resolution = Distillator::FetchMode.resolution(
        explicit_mode: mode,
        website: website,
        website_id: website_id,
        log_context: log_context
      )
      resolved_mode = mode_resolution.mode
      dispatch_mode = Distillator::RolloutResolution.dispatch_mode_for(resolved_mode)
      mode_source = mode_resolution.source
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = fetch_for_mode(
        mode: dispatch_mode,
        mode_source: mode_source,
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        client: client,
        agent: agent,
        use_wringer: use_wringer,
        safe_wringer_call: safe_wringer_call,
        logger: logger,
        log_context: log_context
      )
      result = enrich_wringer_metadata(url: url, result: result)
      elapsed_duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1)

      result = result.merge(duration_ms: result[:duration_ms] || elapsed_duration_ms)
      log_fetch_outcome(logger, mode: resolved_mode, mode_source: mode_source, url: url, result: result, log_context: log_context)
      result
    end

    def self.fetch_for_mode(mode:, mode_source:, url:, render_js:, scrape_options:, client:, agent:, use_wringer:, safe_wringer_call:, logger:, log_context:)
      case mode
      when :active, :internal
        fetch_internal_or_legacy(
          mode_source: mode_source,
          url: url,
          render_js: render_js,
          scrape_options: scrape_options,
          client: client,
          agent: agent,
          use_wringer: use_wringer,
          safe_wringer_call: safe_wringer_call,
          logger: logger,
          log_context: log_context
        )
      when :shadow
        fetch_with_shadow(
          mode_source: mode_source,
          url: url,
          render_js: render_js,
          scrape_options: scrape_options,
          client: client,
          agent: agent,
          use_wringer: use_wringer,
          safe_wringer_call: safe_wringer_call,
          logger: logger,
          log_context: log_context
        )
      else
        legacy_fetch(
          url: url,
          render_js: render_js,
          scrape_options: scrape_options,
          client: client,
          agent: agent,
          use_wringer: use_wringer,
          safe_wringer_call: safe_wringer_call,
          logger: logger,
          log_context: log_context
        ).merge(fetch_path: "legacy")
      end
    end

    def self.fetch_internal_or_legacy(mode_source:, url:, render_js:, scrape_options:, client:, agent:, use_wringer:, safe_wringer_call:, logger:, log_context:)
      eligibility = fetch_eligibility(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        client: client,
        agent: agent,
        use_wringer: use_wringer,
        safe_wringer_call: safe_wringer_call,
        logger: logger
      )
      unless eligibility.eligible?
        log_internal_ineligible(logger, url: url, render_js: render_js, scrape_options: scrape_options, eligibility: eligibility, mode_source: mode_source, log_context: log_context)
        if eligibility.abort?
          return fetch_blocked_result(
            url: url,
            error: eligibility.details[:guard_error] || eligibility.reason.to_s,
            reason: eligibility.reason,
            diagnostic_reason: eligibility.details[:guard_reason]
          )
            .merge(fetch_path: "blocked")
        end

        log_legacy_fallback(logger, url: url, render_js: render_js, scrape_options: scrape_options, eligibility: eligibility, mode_source: mode_source, log_context: log_context)
        return legacy_fetch(
          url: url,
          render_js: render_js,
          scrape_options: scrape_options,
          client: client,
          agent: agent,
          use_wringer: use_wringer,
          safe_wringer_call: safe_wringer_call,
          logger: logger,
          log_context: log_context
        ).then { |result| annotate_ineligibility(result, eligibility).merge(fetch_path: "legacy") }
      end

      log_internal_eligibility(logger, url: url, render_js: render_js, scrape_options: scrape_options, eligibility: eligibility, mode_source: mode_source, log_context: log_context)
      log_fetch_path(logger, path: "native_fetch", url: url, mode_source: mode_source, log_context: log_context)

      guarded_internal_fetch(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        agent: agent,
        use_wringer: use_wringer,
        safe_wringer_call: safe_wringer_call,
        logger: logger
      ).merge(fetch_path: "native")
    end

    def self.fetch_with_shadow(mode_source:, url:, render_js:, scrape_options:, client:, agent:, use_wringer:, safe_wringer_call:, logger:, log_context:)
      eligibility = fetch_eligibility(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        client: client,
        agent: agent,
        use_wringer: use_wringer,
        safe_wringer_call: safe_wringer_call,
        logger: logger
      )
      unless eligibility.eligible?
        log_internal_ineligible(logger, url: url, render_js: render_js, scrape_options: scrape_options, eligibility: eligibility, mode_source: mode_source, log_context: log_context)
        log_shadow_skipped(logger, url: url, render_js: render_js, scrape_options: scrape_options, eligibility: eligibility, mode_source: mode_source, log_context: log_context)
        return fetch_blocked_result(
          url: url,
          error: eligibility.details[:guard_error] || eligibility.reason.to_s,
          reason: eligibility.reason,
          diagnostic_reason: eligibility.details[:guard_reason]
        )
          .merge(fetch_path: "blocked") if eligibility.abort?
      end

      legacy_result = legacy_fetch(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        client: client,
        agent: agent,
        use_wringer: use_wringer,
        safe_wringer_call: safe_wringer_call,
        logger: logger,
        log_context: log_context
      )

      if eligibility.eligible?
        run_shadow_compare(
          legacy_result: legacy_result,
          mode_source: mode_source,
          url: url,
          render_js: render_js,
          scrape_options: scrape_options,
          client: client,
          agent: agent,
          use_wringer: use_wringer,
          safe_wringer_call: safe_wringer_call,
          logger: logger,
          log_context: log_context
        )
      else
        legacy_result = annotate_ineligibility(legacy_result, eligibility)
      end

      legacy_result.merge(fetch_path: "shadow")
    end

    def self.run_shadow_compare(legacy_result:, mode_source:, url:, render_js:, scrape_options:, client:, agent:, use_wringer:, safe_wringer_call:, logger:, log_context:)
      eligibility = fetch_eligibility(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        client: client,
        agent: agent,
        use_wringer: use_wringer,
        safe_wringer_call: safe_wringer_call,
        logger: logger
      )
      unless eligibility.eligible?
        log_internal_ineligible(logger, url: url, render_js: render_js, scrape_options: scrape_options, eligibility: eligibility, mode_source: mode_source, log_context: log_context)
        log_shadow_skipped(logger, url: url, render_js: render_js, scrape_options: scrape_options, eligibility: eligibility, mode_source: mode_source, log_context: log_context)
        return
      end

      log_internal_eligibility(logger, url: url, render_js: render_js, scrape_options: scrape_options, eligibility: eligibility, mode_source: mode_source, log_context: log_context)
      log_fetch_path(logger, path: "native_fetch", url: url, mode_source: mode_source, log_context: log_context)

      internal_result = guarded_internal_fetch(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        agent: agent,
        use_wringer: use_wringer,
        safe_wringer_call: safe_wringer_call,
        logger: logger
      )
      Distillator::FetchShadowComparator.compare(
        url: url,
        legacy: legacy_result,
        internal: internal_result,
        logger: logger || Rails.logger
      )
      (logger || Rails.logger).info(
        structured_log_payload(
          event: "fetch.shadow_compare",
          uri: url,
          mode: "shadow",
          mode_source: mode_source,
          fetch_path: "shadow",
          result: legacy_result,
          log_context: log_context
        )
      )
    rescue StandardError => e
      (logger || Rails.logger).warn(
        event: "distillator.fetch_shadow.error",
        url: url,
        error_class: e.class.name,
        error: e.message
      )
      nil
    end

    def self.use_internal_fetch?(
      url:,
      render_js:,
      scrape_options:,
      client: nil,
      agent: nil,
      use_wringer: nil,
      safe_wringer_call: nil,
      logger: nil
    )
      fetch_eligibility(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        client: client,
        agent: agent,
        use_wringer: use_wringer,
        safe_wringer_call: safe_wringer_call,
        logger: logger
      ).eligible?
    end

    def self.fetch_eligibility(url:, render_js:, scrape_options:, client:, agent:, use_wringer:, safe_wringer_call:, logger:)
      Distillator::FetchEligibility.call(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        client: client
      )
    end

    def self.json_post?(scrape_options)
      opts = scrape_options.is_a?(Hash) ? scrape_options : {}
      Distillator::BooleanParam.parse(opts[:json_post] || opts["json_post"])
    end

    def self.legacy_fetch(
      url:,
      render_js:,
      scrape_options:,
      client: nil,
      agent: nil,
      use_wringer: nil,
      safe_wringer_call: nil,
      logger: nil,
      log_context: {}
    )
      Distillator::LegacyWringerFetch.fetch(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        client: client,
        agent: agent,
        use_wringer: use_wringer,
        safe_wringer_call: safe_wringer_call,
        logger: logger
      )
    end

    def self.internal_fetch(url:, render_js:, scrape_options:, agent: nil, use_wringer: nil, safe_wringer_call: nil, logger: nil, log_context: {})
      Distillator::NativeFetch.fetch(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        agent: agent,
        logger: logger
      )
    end

    def self.guarded_internal_fetch(url:, render_js:, scrape_options:, agent: nil, use_wringer: nil, safe_wringer_call: nil, logger: nil)
      guard = Distillator::FetchGuard.check_url(url)
      return fetch_blocked_result(url: url, error: guard.error, diagnostic_reason: guard.reason) unless guard.allowed?

      result = internal_fetch(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        agent: agent,
        use_wringer: use_wringer,
        safe_wringer_call: safe_wringer_call,
        logger: logger
      )

      redirect_guard = Distillator::FetchGuard.check_response(result)
      return fetch_blocked_result(url: url, error: redirect_guard.error, diagnostic_reason: redirect_guard.reason) unless redirect_guard.allowed?

      result
    end

    def self.fetch_wringer_backed(url:, render_js:, scrape_options:, agent:, use_wringer:, safe_wringer_call:, logger:)
      Distillator::LegacyWringerFetch.fetch_wringer_backed(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        agent: agent,
        use_wringer: use_wringer,
        safe_wringer_call: safe_wringer_call,
        logger: logger
      )
    end

    def self.fetch_blocked_result(url:, error:, reason: :blocked_url, diagnostic_reason: nil)
      payload = [
        "abort_update",
        {
          error: error,
          error_type: "DistillatorFetchBlocked",
          source: "distillator_fetch_guard",
          retry: false,
          cache: false,
          step: "url",
          signals: {
            native_ineligible_reason: reason.to_s,
            guard_reason: (diagnostic_reason || reason).to_s,
            network_status: "blocked"
          },
          hints: [reason.to_s, (diagnostic_reason || reason).to_s, "blocked"].uniq
        }
      ]

      {
        status: :abort,
        body: payload,
        headers: {},
        final_url: url,
        redirect_chain: [],
        wringer: {
          error_type: "DistillatorFetchBlocked",
          source: "distillator_fetch_guard",
          retry: false,
          cache: false,
          signals: {
            native_ineligible_reason: reason.to_s,
            guard_reason: (diagnostic_reason || reason).to_s,
            network_status: "blocked"
          },
          hints: [reason.to_s, (diagnostic_reason || reason).to_s, "blocked"].uniq
        }
      }
    end

    def self.log_internal_ineligible(logger, url:, render_js:, scrape_options:, eligibility:, mode_source:, log_context:)
      (logger || Rails.logger).info(
        {
          event: "distillator.fetch_mode.internal_ineligible",
          url: url,
          render_js: render_js == true,
          json_post: json_post?(scrape_options) == true,
          reason: eligibility.reason,
          policy: eligibility.policy,
          mode_source: mode_source.to_s
        }.merge(eligibility.details).merge(log_context_fields(log_context))
      )
    end

    def self.log_internal_eligibility(logger, url:, render_js:, scrape_options:, eligibility:, mode_source:, log_context:)
      (logger || Rails.logger).info(
        {
          event: "distillator.fetch.eligibility",
          eligible: eligibility.eligible?,
          url: url,
          render_js: render_js == true,
          json_post: json_post?(scrape_options) == true,
          reason: eligibility.reason,
          policy: eligibility.policy,
          mode_source: mode_source.to_s
        }.merge(eligibility.details).merge(log_context_fields(log_context))
      )
    end

    def self.log_shadow_skipped(logger, url:, render_js:, scrape_options:, eligibility:, mode_source:, log_context:)
      (logger || Rails.logger).info(
        {
          event: "distillator.fetch_shadow.skipped",
          url: url,
          render_js: render_js == true,
          json_post: json_post?(scrape_options) == true,
          reason: eligibility.reason,
          policy: eligibility.policy,
          mode_source: mode_source.to_s
        }.merge(eligibility.details).merge(log_context_fields(log_context))
      )
    end

    def self.log_fetch_path(logger, path:, url:, mode_source:, log_context:)
      (logger || Rails.logger).info(
        {
          event: "distillator.fetch.path",
          path: path,
          url: url,
          mode_source: mode_source.to_s
        }.merge(log_context_fields(log_context))
      )
    end

    def self.log_legacy_fallback(logger, url:, render_js:, scrape_options:, eligibility:, mode_source:, log_context:)
      (logger || Rails.logger).warn(
        {
          event: "distillator.fetch.legacy_fallback",
          deprecated: true,
          url: url,
          render_js: Distillator::BooleanParam.parse(render_js),
          json_post: json_post?(scrape_options),
          reason: eligibility.reason,
          policy: eligibility.policy,
          mode_source: mode_source.to_s,
          forced_legacy: eligibility.details[:forced_legacy] == true,
          client: eligibility.details[:client]
        }.merge(log_context_fields(log_context))
      )
    end

    def self.annotate_ineligibility(result, eligibility)
      payload = result.deep_dup
      payload[:wringer] ||= {}
      payload[:wringer][:signals] = normalize_signals(payload.dig(:wringer, :signals)).merge(
        native_ineligible_reason: eligibility.reason.to_s
      )
      payload[:wringer][:hints] = (normalize_hints(payload.dig(:wringer, :hints)) + [eligibility.reason.to_s]).uniq
      payload
    end

    def self.log_fetch_outcome(logger, mode:, mode_source:, url:, result:, log_context:)
      return unless logger || Rails.logger

      event =
        if result[:status] == :abort
          "fetch.abort"
        elsif result[:fetch_path] == "replay"
          "fetch.replay"
        elsif result[:fetch_path] == "legacy"
          "fetch.legacy"
        elsif result[:fetch_path] == "native"
          "fetch.native"
        else
          nil
        end
      return unless event

      (logger || Rails.logger).info(
        structured_log_payload(
          event: event,
          uri: url,
          mode: mode.to_s,
          mode_source: mode_source,
          fetch_path: result[:fetch_path],
          result: result,
          log_context: log_context
        )
      )
    end

    def self.structured_log_payload(event:, uri:, mode:, mode_source:, fetch_path:, result:, log_context:)
      key = Distillator::WringerUrlKey.call(uri)
      signals = normalize_signals(result.dig(:wringer, :signals))
      {
        service: "distillator",
        event: event,
        uri: uri,
        uri_key: key.uri_key,
        mode: mode,
        mode_source: mode_source.to_s,
        fetch_path: fetch_path,
        cache_reason: nil,
        http_response_code: result[:http_code] || result.dig(:wringer, :http_code),
        network_status: signals[:network_status] || signals["network_status"],
        content_type: signals[:content_type] || signals["content_type"],
        redirect_type: signals[:redirect_type] || signals["redirect_type"],
        duration_ms: result[:duration_ms],
      }.merge(log_context_fields(log_context))
    end

    def self.log_context_fields(log_context)
      context = log_context.respond_to?(:to_h) ? log_context.to_h.symbolize_keys : {}
      {
        statement_id: context[:statement_id],
        source_id: context[:source_id],
        webpage_id: context[:webpage_id],
        website_id: context[:website_id]
      }
    end

    def self.enrich_wringer_metadata(url:, result:)
      payload = result.dup
      payload[:wringer] ||= {}

      headers = normalize_headers(payload[:headers] || {})
      body = payload[:raw_body].is_a?(String) ? payload[:raw_body] : (payload[:body].is_a?(String) ? payload[:body] : nil)
      signals = normalize_signals(payload.dig(:wringer, :signals)).dup
      hints = normalize_hints(payload.dig(:wringer, :hints)).dup
      http_code = payload[:http_code] || payload.dig(:wringer, :http_code) || default_http_code_for(payload)

      content_type = detect_content_type(headers, body)
      signals[:content_type] ||= content_type
      signals[:network_status] ||= "ok" if payload[:status] == :ok

      redirected = redirected?(url: url, final_url: payload[:final_url], redirect_chain: payload[:redirect_chain])
      signals[:redirect_type] ||= redirected ? "normal" : "none"
      signals[:redirected] = redirected unless signals.key?(:redirected) || signals.key?("redirected")
      signals[:final_url] ||= payload[:final_url] if payload[:final_url].present?
      signals[:json_detected] = true if content_type == "json"

      hints << "json_detected" if content_type == "json"
      hints << "empty_body" if body.is_a?(String) && body.strip.empty?

      issue_set = Distillator::WringerIssueSet.call(
        body: body,
        http_code: http_code,
        final_url: payload[:final_url],
        hints: hints,
        signals: signals
      )
      issue_set.matches.each do |issue|
        hints.concat(Array(issue.dig(:rule, "hints") || issue.dig(:rule, :hints)))
      end

      issue = issue_set.primary
      if issue
        signals[:primary_issue_key] = issue[:key]
        signals[:primary_issue_error_code] = issue[:error_type]
        signals[:primary_issue_severity] = issue.dig(:rule, "severity") || issue.dig(:rule, :severity)
        signals[:primary_issue_category] = issue.dig(:rule, "category") || issue.dig(:rule, :category)
        signals[:primary_issue_label] = issue.dig(:rule, "label") || issue.dig(:rule, :label)
        signals[:primary_issue_delete] = issue[:delete] unless issue[:delete].nil?
        signals[:issue_keys] = issue_set.matches.map { |match| match[:key] }.uniq
        payload[:wringer][:matched_rule] = issue[:key]
        payload[:wringer][:matched_rules] = issue_set.matches.map { |match| match[:key] }.uniq
        payload[:wringer][:policy] = issue[:policy]
        payload[:wringer][:policy_action] = issue[:action]
        payload[:wringer][:error_type] ||= issue[:error_type]
        payload[:wringer][:retry] = issue[:retry] unless issue[:retry].nil?
        payload[:wringer][:cache] = issue[:cache] unless issue[:cache].nil?
      end

      signals[:transport_success] = transport_success?(status: payload[:status], http_code: http_code)
      signals[:blocking_issue_key] = issue[:key] if issue
      signals[:content_success] = content_success?(
        status: payload[:status],
        http_code: http_code,
        body: body,
        issue: issue,
        policy_action: payload.dig(:wringer, :policy_action)
      )

      payload[:wringer][:signals] = signals
      payload[:wringer][:hints] = hints.uniq
      payload
    end

    def self.transport_success?(status:, http_code:)
      status == :ok && http_code.to_i.between?(200, 299)
    end

    def self.content_success?(status:, http_code:, body:, issue:, policy_action:)
      return false unless transport_success?(status: status, http_code: http_code)
      return false unless body.is_a?(String) && body.present?
      return false if policy_action.to_s == "abort_update"

      severity = issue&.dig(:rule, "severity") || issue&.dig(:rule, :severity)
      return false if %w[blocked failed].include?(severity.to_s)

      true
    end

    def self.detect_content_type(headers, body)
      return "unknown" unless body.is_a?(String)

      content_type_header =
        headers[:content_type] ||
        headers["content_type"] ||
        headers["Content-Type"]

      if content_type_header.to_s.include?("json") || looks_like_json?(body)
        "json"
      elsif content_type_header.to_s.include?("html") || looks_like_html?(body)
        "html"
      else
        "unknown"
      end
    end

    def self.redirected?(url:, final_url:, redirect_chain:)
      chain = normalize_redirect_chain(redirect_chain)
      return true if chain.length > 1
      return false if final_url.blank?

      final_url.to_s != url.to_s
    end

    def self.sanitize_scrape_options(scrape_options, explicit_log_context)
      options =
        if scrape_options.respond_to?(:deep_dup)
          scrape_options.deep_dup.with_indifferent_access
        else
          {}.with_indifferent_access
        end
      extracted_log_context = options.delete(:log_context) || options.delete("log_context") || {}
      [options.to_h.symbolize_keys, normalize_log_context(explicit_log_context, extracted_log_context)]
    end

    def self.normalize_log_context(explicit_log_context, extracted_log_context)
      context = explicit_log_context.presence || extracted_log_context
      context.respond_to?(:to_h) ? context.to_h.symbolize_keys : {}
    end

    def self.response_contract(result, elapsed_duration_ms)
      duration_ms =
        if result.is_a?(Hash) && result.key?(:duration_ms) && !result[:duration_ms].nil?
          result[:duration_ms]
        else
          elapsed_duration_ms
        end

      {
        status: result[:status],
        body: result[:body],
        headers: normalize_headers(result[:headers]),
        final_url: result[:final_url],
        redirect_chain: normalize_redirect_chain(result[:redirect_chain]),
        wringer: result[:wringer],
        duration_ms: duration_ms
      }
    end

    def self.default_http_code_for(result)
      return nil unless result.is_a?(Hash)
      return result.dig(:wringer, :http_code) if result.dig(:wringer, :http_code).present?
      return nil unless result[:status] == :ok

      200
    end

    def self.invoke_safe_wringer_call(safe_wringer_call, &blk)
      safe_wringer_call.call(normalize_response: true, &blk)
    rescue ArgumentError
      safe_wringer_call.call(&blk)
    end

    def self.normalize_fetch_result(result, logger)
      return result if result.is_a?(Hash) && result.key?(:body)

      if result.respond_to?(:code) && result.respond_to?(:body)
        {
          body: result.body,
          http_code: result.code.to_i,
          headers: extract_headers(result),
          final_url: result.respond_to?(:uri) ? result.uri.to_s : nil
        }
      else
        {
          body: result,
          http_code: 200,
          headers: {},
          final_url: nil
        }
      end
    ensure
      unexpected_type =
        !result.is_a?(Hash) &&
        !(result.respond_to?(:code) && result.respond_to?(:body)) &&
        !result.is_a?(String) &&
        !result.nil?
      if unexpected_type
        logger.debug { "[WringerClient] Unexpected body type: #{result.class}" }
      end
    end

    def self.abort_structure?(obj)
      obj.is_a?(Array) &&
        obj.length == 2 &&
        obj.first == "abort_update" &&
        obj.last.is_a?(Hash)
    end

    def self.control_structure?(obj)
      obj.is_a?(Array) &&
        obj.length == 2 &&
        obj.first.is_a?(String)
    end

    def self.normalize_control_result(result)
      return nil unless control_structure?(result)

      action = result.first
      payload = result.second
      payload = payload.to_h if payload.respond_to?(:to_h)

      unless payload.is_a?(Hash)
        payload = {
          error: "Malformed Wringer control payload",
          error_type: "WringerMalformedControlPayload",
          source: "wringer"
        }
      end

      normalized = payload.transform_keys { |k| k.respond_to?(:to_sym) ? k.to_sym : k }

      case action
      when "abort_update"
        if %w[wringer_unreachable wringer_error].include?(normalized[:error_type].to_s)
          normalized[:original_error_type] = normalized[:error_type]
          normalized[:error_type] = "WringerFetchError"
          normalized[:source] ||= "wringer"
          normalized[:step] ||= "url"
        end
        ["abort_update", normalized]
      when "skip"
        ["abort_update", {
          error: "Wringer skipped request",
          error_type: "WringerSkip",
          source: "wringer"
        }]
      else
        ["abort_update", {
          error: "Unsupported Wringer action: #{action}",
          error_type: "WringerUnsupportedAction",
          source: "wringer"
        }]
      end
    end

    def self.build_wringer_status(result, raw_response = nil)
      status = nil

      if abort_structure?(result)
        error_payload = result.last
        return nil unless error_payload.is_a?(Hash)

        policy = error_payload[:policy] || error_payload["policy"] || {}
        policy_action = error_payload[:action] || error_payload["action"] || policy[:action] || policy["action"]

        retry_value = error_payload.key?(:retry) ? error_payload[:retry] : error_payload["retry"]
        cache_value = error_payload.key?(:cache) ? error_payload[:cache] : error_payload["cache"]

        retry_value = policy[:retry] if retry_value.nil? && policy.is_a?(Hash) && policy.key?(:retry)
        retry_value = policy["retry"] if retry_value.nil? && policy.is_a?(Hash) && policy.key?("retry")
        cache_value = policy[:cache] if cache_value.nil? && policy.is_a?(Hash) && policy.key?(:cache)
        cache_value = policy["cache"] if cache_value.nil? && policy.is_a?(Hash) && policy.key?("cache")
        error_type = error_payload[:error_type] || error_payload["error_type"]

        status = {
          error_type: error_type,
          source: error_payload[:source] || error_payload["source"],
          retry: retry_value,
          cache: cache_value,
          signals: normalize_signals(error_payload[:signals] || error_payload["signals"]),
          hints: normalize_hints(error_payload[:hints] || error_payload["hints"])
        }

        if raw_response.respond_to?(:code) && raw_response.respond_to?(:uri)
          status[:http_code] = raw_response.code.to_i
          status[:final_url] = raw_response.uri.to_s
        end

        status[:policy_action] = policy_action if policy_action.present?

        canonical_error_type = error_payload[:original_error_type] || error_payload["original_error_type"] || error_type
        canonical = canonical_wringer_signals(
          error_type: canonical_error_type,
          http_code: status[:http_code],
          policy_action: policy_action
        )
        status.merge!(canonical) if canonical.present?
      elsif result.is_a?(Hash)
        code = result[:http_code].to_i

        if [404, 500, 502, 503, 504].include?(code)
          status = {
            error_type: code == 404 ? "http_404" : "http_server_error",
            http_code: code,
            final_url: result[:final_url]
          }.compact
        end
      end

      status ||= {}

      if raw_response
        status[:signals] ||= extract_signals(raw_response)
        status[:hints] ||= extract_hints(raw_response)
      else
        status[:signals] ||= {}
        status[:hints] ||= []
      end

      status[:signals] = normalize_signals(status[:signals])
      status[:hints] = normalize_hints(status[:hints])

      status
    end

    def self.fetch_metadata(normalized, raw_response, agent)
      {
        headers: normalize_headers(normalized[:headers].presence || extract_headers(raw_response)),
        final_url: normalized[:final_url].presence || extract_final_url(raw_response),
        redirect_chain: extract_redirect_chain(agent)
      }
    end

    def self.extract_headers(raw_response)
      return {} unless raw_response

      headers =
        if raw_response.respond_to?(:response) && raw_response.response
          raw_response.response
        elsif raw_response.respond_to?(:headers)
          raw_response.headers
        else
          {}
        end

      normalize_headers(headers.respond_to?(:to_h) ? headers.to_h : headers)
    rescue StandardError
      {}
    end

    def self.normalize_headers(headers)
      return {} unless headers.is_a?(Hash)

      headers.each_with_object({}) do |(key, value), out|
        out[normalize_header_key(key)] = value
      end
    end

    def self.normalize_header_key(key)
      key.to_s
         .strip
         .downcase
         .tr("-", "_")
         .gsub(/[^a-z0-9_]+/, "_")
         .gsub(/\A_+|_+\z/, "")
         .to_sym
    end

    def self.extract_final_url(raw_response)
      return nil unless raw_response.respond_to?(:uri)

      raw_response.uri.to_s
    rescue StandardError
      nil
    end

    def self.extract_redirect_chain(agent)
      return [] unless agent.respond_to?(:history)

      Array(agent.history).filter_map do |page|
        page.uri.to_s if page.respond_to?(:uri)
      end.uniq
    rescue StandardError
      []
    end

    def self.normalize_redirect_chain(value)
      Array(value).compact.map(&:to_s)
    end

    def self.normalize_signals(value)
      return value if value.is_a?(Hash)

      {}
    end

    def self.normalize_hints(value)
      return value if value.is_a?(Array)

      []
    end

    def self.extract_signals(raw_response)
      return {} unless raw_response

      content_type_header =
        if raw_response.respond_to?(:[])
          raw_response["Content-Type"] || raw_response["content-type"]
        end

      body =
        if raw_response.respond_to?(:body)
          raw_response.body.to_s
        else
          raw_response.to_s
        end

      content_type =
        if content_type_header.to_s.include?("json") || looks_like_json?(body)
          "json"
        elsif content_type_header.to_s.include?("html") || looks_like_html?(body)
          "html"
        else
          "unknown"
        end

      {
        content_type: content_type,
        network_status: "ok"
      }
    rescue StandardError
      {}
    end

    def self.extract_hints(raw_response)
      return [] unless raw_response

      body =
        if raw_response.respond_to?(:body)
          raw_response.body.to_s
        else
          raw_response.to_s
        end

      hints = []
      hints << "empty_body" if body.strip.empty?
      hints
    rescue StandardError
      []
    end

    def self.looks_like_json?(body)
      value = body.to_s.lstrip
      value.start_with?("{", "[")
    end

    def self.looks_like_html?(body)
      value = body.to_s.downcase
      value.include?("<html") || value.include?("<!doctype html")
    end

    def self.canonical_wringer_signals(error_type:, http_code:, policy_action:)
      normalized_error = error_type.to_s
      code = http_code.to_i

      unreachable = normalized_error == "wringer_unreachable"
      received_404 = normalized_error == "http_404" || code == 404
      system_error = normalized_error == "http_server_error" || normalized_error == "wringer_error" || code >= 500

      has_signal = unreachable || received_404 || system_error
      return nil unless has_signal || policy_action.present?

      {
        unreachable: unreachable,
        received_404: received_404,
        system_error: system_error,
        policy_action: policy_action
      }.compact
    end

    private_class_method(
      :fetch_for_mode,
      :fetch_internal_or_legacy,
      :fetch_with_shadow,
      :run_shadow_compare,
      :use_internal_fetch?,
      :fetch_eligibility,
      :legacy_fetch,
      :internal_fetch,
      :guarded_internal_fetch,
      :fetch_blocked_result,
      :log_internal_ineligible,
      :log_internal_eligibility,
      :log_shadow_skipped,
      :log_fetch_path,
      :annotate_ineligibility,
      :log_fetch_outcome,
      :structured_log_payload,
      :detect_content_type,
      :redirected?,
      :response_contract,
      :abort_structure?,
      :control_structure?,
      :extract_headers,
      :normalize_header_key,
      :extract_final_url,
      :extract_redirect_chain,
      :normalize_redirect_chain,
      :extract_signals,
      :extract_hints,
      :looks_like_json?,
      :looks_like_html?,
      :canonical_wringer_signals
    )
  end
end
