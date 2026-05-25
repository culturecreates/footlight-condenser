module Distillator
  class TransitionCheckRunner
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
          export_diff_not_available
          partial_fetch_failed_before_statement_refresh
          partial_fetch_failed_before_export_comparison
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
      refresh_runner: Distillator::RefreshRunner,
      export_service: ExportArtsdataService,
      transition_check_service: Distillator::TransitionCheck,
      fetch_cache_store: Distillator::FetchCacheStore,
      cache_compare: Distillator::CacheCompare
    )
      @website = website.is_a?(Website) ? website : Website.find(website)
      @refresh_helper = refresh_helper || StatementsHelper.build_refresh_proxy(cookies: {})
      @refresh_runner = refresh_runner
      @export_service = export_service
      @transition_check_service = transition_check_service
      @fetch_cache_store = fetch_cache_store
      @cache_compare = cache_compare
    end

    def call
      transition_check = transition_check_service.call(website: website, run_fetch: false)
      representative_webpages = Array(transition_check.representative_webpages)
      representative_url_results = representative_webpages.map do |webpage|
        representative_url_result_for(webpage, transition_check.comparison_policy)
      end

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

    attr_reader :website, :refresh_helper, :refresh_runner, :export_service, :transition_check_service, :fetch_cache_store, :cache_compare

    def record_fetch_check(transition_check, representative_url_results)
      latest_cache = representative_url_results.first&.dig(:cache) || transition_check.cache
      status, details = fetch_check_payload(transition_check, representative_url_results)

      Distillator::TransitionEvidenceRecorder.call(
        website: website,
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

      fetched_webpages, failed_fetch_results = partition_representative_webpages(representative_webpages, representative_url_results)
      statements_scope = representative_statement_scope(fetched_webpages)
      if representative_url_results.all? { |result| result[:fetch_status] == "failed" }
        return Distillator::TransitionEvidenceRecorder.call(
          website: website,
          url: cache_or_seed_url(latest_cache),
          check_kind: :statement_delta,
          status: :pending,
          statement_delta: 0,
          statement_count_delta_acceptable: nil,
          details: scope_details(transition_check, representative_webpages).merge(
            source: "statement_refresh",
            representative_url_statement_results: representative_url_results.map do |result|
              {
                url: result[:url],
                status: "blocked_by_fetch",
                reason: result[:fetch_reason]
              }
            end,
            statements_refreshed_count: 0,
            statements_failed_count: 0,
            failing_statement_ids: [],
            failing_statements: [],
            reason: "fetch_failed_before_statement_refresh"
          )
        )
      end

      if statements_scope.none?
        return Distillator::TransitionEvidenceRecorder.call(
          website: website,
          url: cache_or_seed_url(latest_cache),
          check_kind: :statement_delta,
          status: :pending,
          statement_delta: 0,
          statement_count_delta_acceptable: nil,
          details: scope_details(transition_check, representative_webpages).merge(
            source: "statement_refresh",
            statements_refreshed_count: 0,
            statements_failed_count: 0,
            failing_statement_ids: [],
            failing_statements: [],
            reason: "no_selected_statements"
          )
        )
      end

      refresh_errors = fetched_webpages.flat_map do |webpage|
        refresh_runner.call(
          webpage: webpage,
          refresh_helper: refresh_helper,
          scrape_options: { force_scrape_every_hrs: 0 }
        )
      end
      failing_statements = representative_problem_statements(fetched_webpages)
      scope_statements = statements_scope.to_a
      reported_failing_statements = refresh_errors.present? ? scope_statements : failing_statements
      statement_delta = failing_statements.count
      statement_results_by_url = representative_statement_results(fetched_webpages, failed_fetch_results, refresh_errors, failing_statements)
      details = scope_details(transition_check, representative_webpages).merge(
        source: "statement_refresh",
        representative_url_statement_results: statement_results_by_url,
        statements_refreshed_count: statements_scope.count,
        statements_failed_count: [statement_delta, reported_failing_statements.count].max,
        failing_statement_ids: reported_failing_statements.map(&:id),
        failing_statements: failing_statement_details(reported_failing_statements)
      )

      if refresh_errors.present?
        status = :failed
        details[:reason] = "statement_refresh_failed"
        details[:refresh_errors] = compact_refresh_errors(refresh_errors)
      elsif failed_fetch_results.any?
        status = :pending
        details[:reason] = "partial_fetch_failed_before_statement_refresh"
      elsif statement_delta.zero?
        status = :checked
      else
        status = :failed
      end

      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        url: cache_or_seed_url(latest_cache),
        check_kind: :statement_delta,
        status: status,
        statement_delta: statement_delta,
        statement_count_delta_acceptable: status == :checked ? true : false,
        details: details
      )
    rescue StandardError => error
      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        url: representative_webpages.first&.url.presence || cache_or_seed_url(latest_cache),
        check_kind: :statement_delta,
        status: :failed,
        statement_count_delta_acceptable: false,
        details: failure_details("statement_refresh_failed", error)
      )
    end

    def record_export_check(transition_check, representative_webpages, representative_url_results)
      latest_cache = representative_url_results.first&.dig(:cache) || transition_check.cache
      return record_missing_representatives(latest_cache, :export_diff, transition_check) if representative_webpages.blank?
      _fetched_webpages, failed_fetch_results = partition_representative_webpages(representative_webpages, representative_url_results)

      if representative_url_results.all? { |result| result[:fetch_status] == "failed" }
        return Distillator::TransitionEvidenceRecorder.call(
          website: website,
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

      if representative_url_results.any? { |result| result[:legacy_lookup_status] == "missing_config" }
        return [:checked, details.merge(reason: "legacy_lookup_missing_config", comparison_performed: false)]
      end

      if representative_url_results.any? { |result| result[:legacy_lookup_status] == "unreachable" }
        return [:checked, details.merge(reason: "legacy_lookup_unreachable", comparison_performed: false)]
      end

      if representative_url_results.any? { |result| result[:legacy_lookup_status] == "body_omitted" }
        return [:checked, details.merge(reason: "legacy_lookup_body_omitted", comparison_performed: false)]
      end

      if representative_url_results.any? { |result| result[:comparison_status] == "review" }
        return [:checked, details.merge(reason: "review_needed_difference")]
      end

      if representative_url_results.any? { |result| result[:comparison_status] == "unknown" }
        return [:failed, details.merge(reason: "cache_compare_unknown")]
      end

      if representative_url_results.any? { |result| result[:comparison_status] == "metadata_only" } &&
         representative_url_results.none? { |result| %w[failed review unknown].include?(result[:comparison_status]) }
        return [:checked, details.merge(reason: "metadata_only_difference")]
      end

      if representative_url_results.any? { |result| result[:comparison_status] == "missing" }
        return [:failed, details.merge(reason: "cache_compare_missing")]
      end

      if representative_url_results.any? { |result| result[:comparison_status] == "failed" }
        return [:failed, details.merge(reason: "cache_compare_blocking_regression")]
      end

      [:checked, details.merge(reason: "ok")]
    end

    def cache_or_seed_url(cache)
      cache&.normalized_url.presence || website.webpages.first&.url.presence || website.seedurl
    end

    def fetch_failure_reason_from_result(result)
      return "missing_condenser_attempt" unless result.present?
      return "empty_body" if truthy?(cache_signal(result.cache, :empty_body))

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

    def representative_statement_scope(representative_webpages)
      Statement
        .selected_for_transition
        .includes(:source, :webpage)
        .where(webpage_id: representative_webpages.map(&:id))
    end

    def representative_problem_statements(representative_webpages)
      representative_statement_scope(representative_webpages)
        .select(&:transition_problem?)
    end

    def failing_statement_details(statements)
      statements.map do |statement|
        {
          id: statement.id,
          webpage_url: statement.webpage&.url,
          source: [statement.source&.property&.label, statement.source&.language].compact.join(" / ")
        }
      end
    end

    def compact_refresh_errors(refresh_errors)
      Array(refresh_errors).flat_map do |entry|
        entry.to_h.flat_map do |label, messages|
          next "#{label}: unknown error" if messages.blank?

          Array(messages).map do |message|
            detail = message.is_a?(Hash) ? message.to_h : message
            "#{label}: #{detail.inspect}"
          end
        end
      end.compact
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
      {
        representative_webpages: representative_webpages.map(&:url),
        representative_webpage_count: representative_webpages.count,
        candidate_webpage_count: transition_check.candidate_webpage_count,
        selected_candidate_tier_count: transition_check.selected_candidate_tier_count,
        selection_rule: transition_check.selection_rule,
        sample_small: transition_check.candidate_webpage_count.to_i > representative_webpages.count
      }
    end

    def representative_url_result_for(webpage, comparison_policy)
      fetch_result = fetch_cache_store.fetch(
        uri: webpage.url,
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

      build_representative_url_result(webpage, fetch_result, comparison)
    end

    def build_representative_url_result(webpage, fetch_result, comparison)
      fetch_status = fetch_result.transport_success? && fetch_result.content_success? ? "passed" : "failed"
      {
        url: webpage.url,
        webpage_id: webpage.id,
        cache: fetch_result.cache,
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
      result.except(:cache)
    end

    def representative_failed_layer(results)
      return "fetch" if results.any? { |result| result[:fetch_status] == "failed" }
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

    def representative_statement_results(representative_webpages, failed_fetch_results, refresh_errors, failing_statements)
      failing_ids = failing_statements.map(&:id)
      rows = representative_webpages.map do |webpage|
        webpage_statements = Statement.selected_for_transition.where(webpage_id: webpage.id).to_a
        status =
          if refresh_errors.present?
            "failed"
          elsif webpage_statements.empty?
            "inconclusive"
          elsif webpage_statements.any? { |statement| failing_ids.include?(statement.id) }
            "failed"
          else
            "passed"
          end

        reason =
          if refresh_errors.present?
            "statement_refresh_failed"
          elsif webpage_statements.empty?
            "no_selected_statements"
          elsif status == "failed"
            "statement_delta"
          else
            "ok"
          end

        {
          url: webpage.url,
          status: status,
          reason: reason,
          failing_statement_ids: webpage_statements.select { |statement| failing_ids.include?(statement.id) }.map(&:id)
        }
      end
      rows + failed_fetch_results.map do |result|
        {
          url: result[:url],
          status: "blocked_by_fetch",
          reason: result[:fetch_reason]
        }
      end
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
  end
end
