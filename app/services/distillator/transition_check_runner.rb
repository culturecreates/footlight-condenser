module Distillator
  class TransitionCheckRunner
    REQUEST_BUDGET_SECONDS = 20
    TIMEOUT_GUARD_SECONDS = 3

    Result = Struct.new(:website, :records, keyword_init: true) do
      def flash_message
        prefix = complete? ? "Transition check recorded:" : "Transition check incomplete:"
        "#{prefix} #{summary_items.join(', ')}"
      end

      def complete?
        summary_statuses.values.all? { |status| status == "checked" }
      end

      def summary_statuses
        records.transform_values { |record| summary_status_for(record) }
      end

      private

      def summary_status_for(record)
        reason = record.details.to_h["reason"] || record.details.to_h[:reason]
        return "not evaluated" if reason == "fetch_failed_before_statement_refresh"
        return "blocked by fetch" if reason == "fetch_failed_before_export_comparison"
        return "inconclusive" if %w[
          no_selected_statements
          paired_extraction_inconclusive
          export_diff_not_available
          partial_fetch_failed_before_statement_refresh
          partial_fetch_failed_before_export_comparison
          transition_check_timeout_budget_exceeded
        ].include?(reason)

        case record.status.to_s
        when "checked", "accepted"
          "checked"
        when "failed", "blocked", "rejected"
          "failed"
        else
          "missing"
        end
      end

      def summary_items
        [
          "fetch #{summary_statuses.fetch(:fetch_parity)}",
          "statements #{summary_statuses.fetch(:statement_delta)}",
          "export #{summary_statuses.fetch(:export_diff)}"
        ]
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(
      website:,
      refresh_helper: nil,
      transition_run: nil,
      statement_comparator: Distillator::MigrationComparator,
      refresh_runner: Distillator::RefreshRunner,
      export_service: ExportArtsdataService,
      transition_check_service: Distillator::TransitionCheck,
      fetch_cache_store: Distillator::FetchCacheStore,
      cache_compare: Distillator::CacheCompare,
      budget_seconds: nil,
      timeout_guard_seconds: TIMEOUT_GUARD_SECONDS,
      clock: nil
    )
      @transition_run = transition_run
      @statement_comparator = statement_comparator
      @website = website.is_a?(Website) ? website : Website.find(website)
      @refresh_helper = refresh_helper || StatementsHelper.build_refresh_proxy(cookies: {})
      @export_service = export_service
      @transition_check_service = transition_check_service
      @fetch_cache_store = fetch_cache_store
      @cache_compare = cache_compare
      @budget_seconds = budget_seconds
      @timeout_guard_seconds = timeout_guard_seconds
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @started_at = monotonic_now
      @representative_result_cache = {}
    end

    def call
      return perform_checks if transition_run

      request = Distillator::TransitionRun.request!(website: website)
      raise "A transition check is already running" unless request.created?
      @transition_run = request.run
      transition_run.execute { perform_checks }
    end

    def perform_checks
      transition_check = transition_check_service.call(website: website, run_fetch: false)
      representative_webpages = Array(transition_check.representative_webpages)
      representative_url_results = collect_representative_url_results(representative_webpages, transition_check.comparison_policy)

      Result.new(
        website: website,
        records: {
          fetch_parity: record_fetch_check(transition_check, representative_url_results),
          statement_delta: record_statement_check(transition_check, representative_webpages, representative_url_results),
          export_diff: record_export_check(transition_check, representative_webpages, representative_url_results)
        }
      )
    end

    private

    attr_reader :transition_run, :statement_comparator, :website, :refresh_helper, :export_service, :transition_check_service, :fetch_cache_store, :cache_compare,
                :budget_seconds, :timeout_guard_seconds

    def record_fetch_check(transition_check, representative_url_results)
      latest_cache = representative_url_results.first&.dig(:cache) || transition_check.cache
      status, details = fetch_check_payload(transition_check, representative_url_results)

      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        transition_run: transition_run,
        url: representative_url_results.first&.dig(:url).presence || transition_check.representative_url.presence || cache_or_seed_url(latest_cache),
        check_kind: :fetch_parity,
        status: status,
        primary_issue_key: latest_cache&.primary_issue_key,
        wringer_http_code: latest_cache&.http_response_code,
        distillator_http_code: latest_cache&.http_response_code,
        details: details
      )
    end

    def record_statement_check(transition_check, representative_webpages, representative_url_results)
      latest_cache = representative_url_results.first&.dig(:cache) || transition_check.cache
      return record_missing_representatives(latest_cache, :statement_delta, transition_check) if representative_webpages.blank?
      if timeout_budget_exceeded?
        fetched, failed = partition_representative_webpages(representative_webpages, representative_url_results)
        return pending_statement_timeout_record(latest_cache, transition_check, representative_webpages, fetched, failed)
      end
      parity = Distillator::StatementParityCheck.call(website: website, webpages: representative_webpages,
        url_results: representative_url_results, refresh_helper: refresh_helper, comparator: statement_comparator)
      failing = parity.critical_failures + parity.optional_failures
      Distillator::TransitionEvidenceRecorder.call(
        website: website, transition_run: transition_run,
        url: representative_webpages.first&.url.presence || cache_or_seed_url(latest_cache),
        check_kind: :statement_delta, status: parity.status,
        statement_delta: parity.critical_failures.length,
        statement_count_delta_acceptable: parity.status.in?(%i[checked warning]),
        details: scope_details(transition_check, representative_webpages).merge(
          source: "paired_extraction", comparison_basis: "paired_dsl", reason: parity.reason,
          representative_url_statement_results: parity.url_results,
          statement_artifacts: parity.artifacts,
          statements_compared_count: parity.artifacts.length, statements_refreshed_count: 0,
          statements_failed_count: failing.length, failing_statements: failing,
          critical_statements_failed_count: parity.critical_failures.length,
          optional_statements_failed_count: parity.optional_failures.length,
          critical_failing_statements: parity.critical_failures,
          optional_failing_statements: parity.optional_failures
        )
      )
    end

    def record_export_check(transition_check, representative_webpages, representative_url_results)
      latest_cache = representative_url_results.first&.dig(:cache) || transition_check.cache
      return record_missing_representatives(latest_cache, :export_diff, transition_check) if representative_webpages.blank?
      fetched_webpages, failed_fetch_results = partition_representative_webpages(representative_webpages, representative_url_results)

      if timeout_budget_exceeded?
        return pending_export_timeout_record(latest_cache, transition_check, representative_webpages, fetched_webpages, failed_fetch_results)
      end

      if representative_url_results.all? { |result| result[:fetch_status] == "failed" }
        return Distillator::TransitionEvidenceRecorder.call(
          website: website,
          transition_run: transition_run,
          url: cache_or_seed_url(latest_cache),
          check_kind: :export_diff,
          status: :pending,
          export_diff_status: "pending",
          details: scope_details(transition_check, representative_webpages).merge(
            source: "export_comparison",
            export_compared: false,
            export_basis: "current export vs production-equivalent export",
            representative_url_export_results: representative_url_results.map do |result|
              {
                url: result[:url],
                status: "blocked_by_fetch",
                reason: result[:fetch_reason]
              }
            end,
            reason: "fetch_failed_before_export_comparison"
          )
        )
      end

      actual = export_service.call(seedurl: website.seedurl)
      expected = export_service.production_equivalent(seedurl: website.seedurl)
      if Distillator::ExportNormalizer.blank_export?(actual) || Distillator::ExportNormalizer.blank_export?(expected)
        return Distillator::TransitionEvidenceRecorder.call(
          website: website,
          transition_run: transition_run,
          url: cache_or_seed_url(latest_cache),
          check_kind: :export_diff,
          status: :pending,
          export_diff_status: "pending",
          details: scope_details(transition_check, representative_webpages).merge(
            source: "export_comparison",
            export_compared: false,
            export_basis: "current export vs production-equivalent export",
            representative_url_export_results: representative_export_results(representative_webpages, failed_fetch_results, "inconclusive", "export_diff_not_available"),
            reason: "export_diff_not_available"
          )
        )
      end

      normalized_actual = Distillator::ExportNormalizer.normalize(actual)
      normalized_expected = Distillator::ExportNormalizer.normalize(expected)
      diff = Distillator::GraphDiff.call(expected_graph: normalized_expected, actual_graph: normalized_actual)
      failed = diff.added_count.positive? || diff.removed_count.positive? || diff.changed_literal_values.any? || diff.changed_uri_objects.any?
      status = failed ? :failed : :checked
      partial_fetch_coverage = failed_fetch_results.any?
      effective_status = partial_fetch_coverage ? :pending : status
      effective_export_checked = partial_fetch_coverage ? false : (status == :checked)
      effective_export_diff_status = partial_fetch_coverage ? "partial" : status.to_s

      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        transition_run: transition_run,
        url: cache_or_seed_url(latest_cache),
        check_kind: :export_diff,
        status: effective_status,
        export_diff_checked: effective_export_checked,
        export_diff_status: effective_export_diff_status,
        export_diff_accepted: false,
        rdf_added_count: diff.added_count,
        rdf_removed_count: diff.removed_count,
        details: scope_details(transition_check, representative_webpages).merge(
          source: "export_comparison",
          export_compared: !partial_fetch_coverage,
          graph_diff_performed: true,
          export_basis: "current export vs production-equivalent export",
          representative_url_export_results: representative_export_results(representative_webpages, failed_fetch_results, status.to_s, status == :checked ? "ok" : "export_diff_detected"),
          reason: partial_fetch_coverage ? "partial_fetch_failed_before_export_comparison" : nil,
          changed_literal_values: diff.changed_literal_values.first(10),
          changed_uri_objects: diff.changed_uri_objects.first(10)
        ).compact
      )
    rescue StandardError => error
      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        transition_run: transition_run,
        url: cache_or_seed_url(latest_cache),
        check_kind: :export_diff,
        status: :failed,
        export_diff_status: "failed",
        details: scope_details(transition_check, representative_webpages).merge(
          export_compared: false,
          export_basis: "current export vs production-equivalent export"
        ).merge(failure_details("export_generation_failed", error))
      )
    end

    def fetch_check_payload(transition_check, representative_url_results)
      cache = representative_url_results.first&.dig(:cache) || transition_check.cache
      representative_webpages = Array(transition_check.representative_webpages)
      details = scope_details(transition_check, representative_webpages).merge(
        source: "transition_check",
        attempted_condenser_fetch: representative_url_results.any? { |result| result[:attempted_condenser_fetch] },
        condenser_fetch_success: representative_url_results.any? { |result| result[:fetch_status] == "passed" },
        comparison_performed: representative_url_results.any? { |result| result[:comparison_performed] },
        comparison_policy: transition_check.comparison_policy.to_s,
        legacy_source: representative_url_results.first&.dig(:legacy_source),
        legacy_lookup_status: representative_url_results.first&.dig(:legacy_lookup_status),
        legacy_lookup_error: representative_url_results.first&.dig(:legacy_lookup_error),
        condenser_source: representative_url_results.first&.dig(:condenser_source),
        compare_missing: representative_url_results.first&.dig(:compare_missing),
        compare_summary: representative_url_results.first&.dig(:compare_summary),
        representative_url_results: representative_url_results.map { |result| serializable_representative_url_result(result) },
        failed_layer: representative_failed_layer(representative_url_results),
        affected_url_count: representative_affected_url_count(representative_url_results),
        representative_urls_checked: representative_url_results.any?
      ).compact

      unless representative_webpages.present?
        return [:pending, details.merge(reason: "no_representative_webpages", representative_urls_checked: false)]
      end

      unless cache.present?
        return [:failed, details.merge(reason: "missing_cache")]
      end

      if representative_url_results.any? { |result| result[:fetch_status] == "failed" }
        failed_result = representative_url_results.find { |result| result[:fetch_status] == "failed" }
        return [:failed, details.merge(reason: failed_result[:fetch_reason] || "cache_health_failed")]
      end

      # Aggregate blockers across the whole sample before considering review or
      # unavailable legacy metadata on another URL.
      if representative_url_results.any? { |result| result[:comparison_status] == "failed" }
        return [:failed, details.merge(reason: "cache_compare_blocking_regression")]
      end
      if representative_url_results.any? { |result| result[:comparison_status] == "unknown" }
        return [:failed, details.merge(reason: "cache_compare_unknown")]
      end
      unavailable_legacy = %w[missing_config unreachable body_omitted]
      if representative_url_results.any? { |result| result[:comparison_status] == "missing" && !unavailable_legacy.include?(result[:legacy_lookup_status]) }
        return [:failed, details.merge(reason: "cache_compare_missing")]
      end
      unavailable_legacy.each do |lookup_status|
        if representative_url_results.any? { |result| result[:legacy_lookup_status] == lookup_status }
          return [:checked, details.merge(reason: "legacy_lookup_#{lookup_status}", comparison_performed: false)]
        end
      end
      if representative_url_results.any? { |result| result[:comparison_status] == "review" }
        return [:checked, details.merge(reason: "review_needed_difference")]
      end
      if representative_url_results.any? { |result| result[:comparison_status] == "metadata_only" }
        return [:checked, details.merge(reason: "metadata_only_difference")]
      end

      [:checked, details.merge(reason: "ok")]
    end

    def cache_or_seed_url(cache)
      cache&.normalized_url.presence || website.webpages.first&.url.presence || website.seedurl
    end

    def fetch_failure_reason_from_result(result)
      return "missing_condenser_attempt" unless result.present?
      return "empty_body" if truthy?(cache_signal(result.cache, :empty_body))
      return "captcha_detected" if captcha_result?(result)
      return missing_renderer_reason(result) if missing_renderer_reason(result).present?

      result.blocking_issue_key.presence ||
        cache_signal(result.cache, :primary_issue_key).presence ||
        cache_signal(result.cache, :network_status).presence ||
        "cache_health_failed"
    end

    def cache_signal(cache, key)
      return nil unless cache.present?

      signals = (cache.signals || {}).to_h
      return signals[key.to_s] if signals.key?(key.to_s)
      return signals[key.to_sym] if signals.key?(key.to_sym)

      nil
    end

    def truthy?(value)
      value == true || value.to_s == "true" || value.to_s == "1"
    end

    def record_missing_representatives(latest_cache, check_kind, transition_check)
      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        transition_run: transition_run,
        url: cache_or_seed_url(latest_cache),
        check_kind: check_kind,
        status: :pending,
        export_diff_status: check_kind == :export_diff ? "pending" : nil,
        details: scope_details(transition_check, []).merge(
          source: "transition_check",
          export_compared: check_kind == :export_diff ? false : nil,
          export_basis: check_kind == :export_diff ? "current export vs production-equivalent export" : nil,
          statements_refreshed_count: check_kind == :statement_delta ? 0 : nil,
          statements_failed_count: check_kind == :statement_delta ? 0 : nil,
          reason: "no_representative_webpages"
        ).compact
      )
    end

    def failure_details(reason, error)
      {
        source: "transition_check",
        reason: reason,
        error_class: error.class.name,
        error_message: error.message
      }
    end

    def scope_details(transition_check, representative_webpages)
      publishable_event_page_count = transition_check.publishable_event_page_count.to_i
      {
        representative_webpages: representative_webpages.map(&:url),
        representative_webpage_count: representative_webpages.count,
        candidate_webpage_count: transition_check.candidate_webpage_count,
        publishable_event_page_count: publishable_event_page_count,
        selected_candidate_tier_count: transition_check.selected_candidate_tier_count,
        selection_rule: transition_check.selection_rule,
        sample_small: (publishable_event_page_count.positive? ? publishable_event_page_count : transition_check.candidate_webpage_count.to_i) > representative_webpages.count
      }
    end

    def representative_url_result_for(webpage, comparison_policy)
      cached = @representative_result_cache[webpage.url]
      return cached.merge(url: webpage.url, webpage_id: webpage.id) if cached.present?

      fetch_result = fetch_cache_store.fetch(
        uri: webpage.url,
        render_js: Statements::RefreshWebpageStatementsService.sources_for_webpage(webpage,
          default_language: website.default_language).any? { |source| source.selected? && source.render_js == true },
        force_scrape: true,
        mode: "internal",
        website: website,
        log_context: {
          source: "transition_check",
          website_id: website.id,
          seedurl: website.seedurl
        }
      )
      comparison = cache_compare.call(
        uri: webpage.url,
        condenser_result: fetch_result,
        comparison_policy: comparison_policy
      )

      built = build_representative_url_result(webpage, fetch_result, comparison)
      @representative_result_cache[webpage.url] = built
      built
    end

    def build_representative_url_result(webpage, fetch_result, comparison)
      fetch_status = fetch_result.transport_success? && fetch_result.content_success? ? "passed" : "failed"
      {
        url: webpage.url,
        webpage_id: webpage.id,
        cache: fetch_result.cache,
        legacy_html: comparison&.dig(:legacy_cache, :html),
        condenser_html: fetch_result.cache&.html,
        attempted_condenser_fetch: true,
        condenser_fetch_success: fetch_status == "passed",
        http_response_code: fetch_result.cache&.http_response_code,
        cache_health_status: fetch_result.cache&.health_status,
        stored_html: fetch_result.cache&.html.present?,
        stored_body_bytes: fetch_result.cache&.body.to_s.bytesize,
        fetch_status: fetch_status,
        fetch_reason: fetch_status == "failed" ? fetch_failure_reason_from_result(fetch_result) : "ok",
        comparison_performed: comparison.present?,
        legacy_source: comparison&.dig(:legacy_source),
        legacy_lookup_status: comparison&.dig(:legacy_lookup_status),
        legacy_lookup_error: comparison&.dig(:legacy_lookup_error),
        condenser_source: comparison&.dig(:condenser_source),
        compare_missing: comparison&.dig(:missing),
        compare_summary: comparison&.dig(:summary),
        comparison_status: comparison_status(comparison)
      }
    end

    def collect_representative_url_results(representative_webpages, comparison_policy)
      collected = []

      representative_webpages.each_with_index do |webpage, index|
        if timeout_budget_exceeded?
          return collected + representative_webpages.drop(index).map { |remaining| timed_out_representative_url_result(remaining) }
        end

        collected << representative_url_result_for(webpage, comparison_policy)
      end

      collected
    end

    def comparison_status(comparison)
      return "not_performed" if comparison.blank?
      return "missing" if comparison.dig(:missing, :legacy) || comparison.dig(:missing, :condenser)
      return "failed" if comparison.dig(:summary, :blocking_regressions).present?
      return "review" if comparison.dig(:summary, :review_needed_diffs).present?
      return "unknown" if comparison.dig(:summary, :unknown_diffs).present?
      return "metadata_only" if comparison.dig(:summary, :metadata_only_diffs).present?

      "passed"
    end

    def serializable_representative_url_result(result)
      result.except(:cache, :legacy_html, :condenser_html)
    end

    def representative_failed_layer(results)
      return "fetch" if results.any? { |result| result[:fetch_status] == "failed" }
      return "cache_compare" if results.any? { |result| result[:comparison_status] == "failed" }
      return "legacy_lookup" if results.any? { |result| %w[missing_config unreachable body_omitted].include?(result[:legacy_lookup_status]) }
      return "cache_compare" if results.any? { |result| %w[failed review unknown missing].include?(result[:comparison_status]) }

      nil
    end

    def representative_affected_url_count(results)
      return results.count { |result| result[:fetch_status] == "failed" } if representative_failed_layer(results) == "fetch"
      return results.count { |result| %w[missing_config unreachable body_omitted].include?(result[:legacy_lookup_status]) } if representative_failed_layer(results) == "legacy_lookup"
      return results.count { |result| %w[failed review unknown missing].include?(result[:comparison_status]) } if representative_failed_layer(results) == "cache_compare"

      0
    end

    def representative_export_results(representative_webpages, failed_fetch_results, status, reason)
      representative_webpages.map do |webpage|
        { url: webpage.url, status: status, reason: reason }
      end + failed_fetch_results.map do |result|
        { url: result[:url], status: "blocked_by_fetch", reason: result[:fetch_reason] }
      end
    end

    def partition_representative_webpages(representative_webpages, representative_url_results)
      results_by_url = representative_url_results.index_by { |result| result[:url] }
      fetched_webpages = representative_webpages.select { |webpage| results_by_url.fetch(webpage.url, {})[:fetch_status] != "failed" }
      failed_fetch_results = representative_url_results.select { |result| result[:fetch_status] == "failed" }
      [fetched_webpages, failed_fetch_results]
    end

    def pending_statement_timeout_record(latest_cache, transition_check, representative_webpages, fetched_webpages, failed_fetch_results)
      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        transition_run: transition_run,
        url: cache_or_seed_url(latest_cache),
        check_kind: :statement_delta,
        status: :pending,
        statement_delta: 0,
        statement_count_delta_acceptable: nil,
        details: scope_details(transition_check, representative_webpages).merge(
          source: "paired_extraction",
          representative_url_statement_results: representative_statement_timeout_results(fetched_webpages, failed_fetch_results),
          statements_refreshed_count: 0,
          statements_failed_count: 0,
          failing_statement_ids: [],
          failing_statements: [],
          reason: "transition_check_timeout_budget_exceeded"
        )
      )
    end

    def pending_export_timeout_record(latest_cache, transition_check, representative_webpages, fetched_webpages, failed_fetch_results)
      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        transition_run: transition_run,
        url: cache_or_seed_url(latest_cache),
        check_kind: :export_diff,
        status: :pending,
        export_diff_checked: false,
        export_diff_status: "pending",
        details: scope_details(transition_check, representative_webpages).merge(
          source: "export_comparison",
          export_compared: false,
          export_basis: "current export vs production-equivalent export",
          representative_url_export_results: representative_export_timeout_results(fetched_webpages, failed_fetch_results),
          reason: "transition_check_timeout_budget_exceeded"
        )
      )
    end

    def representative_statement_timeout_results(fetched_webpages, failed_fetch_results)
      fetched_webpages.map do |webpage|
        {
          url: webpage.url,
          status: "inconclusive",
          reason: "transition_check_timeout_budget_exceeded"
        }
      end + failed_fetch_results.map do |result|
        {
          url: result[:url],
          status: "blocked_by_fetch",
          reason: result[:fetch_reason]
        }
      end
    end

    def representative_export_timeout_results(fetched_webpages, failed_fetch_results)
      fetched_webpages.map do |webpage|
        {
          url: webpage.url,
          status: "inconclusive",
          reason: "transition_check_timeout_budget_exceeded"
        }
      end + failed_fetch_results.map do |result|
        {
          url: result[:url],
          status: "blocked_by_fetch",
          reason: result[:fetch_reason]
        }
      end
    end

    def timed_out_representative_url_result(webpage)
      {
        url: webpage.url,
        webpage_id: webpage.id,
        cache: nil,
        attempted_condenser_fetch: false,
        condenser_fetch_success: false,
        http_response_code: nil,
        cache_health_status: nil,
        stored_html: false,
        stored_body_bytes: 0,
        fetch_status: "failed",
        fetch_reason: "transition_check_timeout_budget_exceeded",
        comparison_performed: false,
        legacy_source: nil,
        legacy_lookup_status: nil,
        legacy_lookup_error: nil,
        condenser_source: nil,
        compare_missing: nil,
        compare_summary: nil,
        comparison_status: "not_performed"
      }
    end

    def timeout_budget_exceeded?
      return false unless budget_seconds.present?

      elapsed = monotonic_now - @started_at
      elapsed >= [budget_seconds.to_f - timeout_guard_seconds.to_f, 0].max
    end

    def monotonic_now
      @clock.call.to_f
    end

    def captcha_result?(result)
      issue_key = result.blocking_issue_key.presence || cache_signal(result.cache, :primary_issue_key).presence
      return true if issue_key.to_s == "system_captcha"

      Array(result.respond_to?(:hints) ? result.hints : nil).map(&:to_s).any? { |hint| hint.include?("captcha") }
    end

    def missing_renderer_reason(result)
      return nil unless truthy?(cache_signal(result.cache, :renderer_unavailable))

      if truthy?(cache_signal(result.cache, :use_phantomjs)) && ENV["PHANTOMJS_API_KEY"].blank?
        "phantomjs_api_key_missing"
      else
        "renderer_unavailable"
      end
    end
  end
end
