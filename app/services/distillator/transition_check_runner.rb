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
        return "inconclusive" if %w[no_selected_statements export_diff_not_available].include?(reason)

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
      transition_check_service: Distillator::TransitionCheck
    )
      @website = website.is_a?(Website) ? website : Website.find(website)
      @refresh_helper = refresh_helper || StatementsHelper.build_refresh_proxy(cookies: {})
      @refresh_runner = refresh_runner
      @export_service = export_service
      @transition_check_service = transition_check_service
    end

    def call
      transition_check = transition_check_service.call(website: website, run_fetch: true)
      representative_webpages = Array(transition_check.representative_webpages)

      Result.new(
        website: website,
        records: {
          fetch_parity: record_fetch_check(transition_check),
          statement_delta: record_statement_check(transition_check, representative_webpages),
          export_diff: record_export_check(transition_check, representative_webpages)
        }
      )
    end

    private

    attr_reader :website, :refresh_helper, :refresh_runner, :export_service, :transition_check_service

    def record_fetch_check(transition_check)
      latest_cache = transition_check.cache
      status, details = fetch_check_payload(transition_check)

      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        url: transition_check.representative_url.presence || cache_or_seed_url(latest_cache),
        check_kind: :fetch_parity,
        status: status,
        primary_issue_key: latest_cache&.primary_issue_key,
        wringer_http_code: latest_cache&.http_response_code,
        distillator_http_code: latest_cache&.http_response_code,
        details: details
      )
    end

    def record_statement_check(transition_check, representative_webpages)
      latest_cache = transition_check.cache
      return record_missing_representatives(latest_cache, :statement_delta, transition_check) if representative_webpages.blank?

      statements_scope = representative_statement_scope(representative_webpages)
      if transition_check.fetch == :failed
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

      refresh_errors = representative_webpages.flat_map do |webpage|
        refresh_runner.call(
          webpage: webpage,
          refresh_helper: refresh_helper,
          scrape_options: { force_scrape_every_hrs: 0 }
        )
      end
      failing_statements = representative_problem_statements(representative_webpages)
      scope_statements = statements_scope.to_a
      reported_failing_statements = refresh_errors.present? ? scope_statements : failing_statements
      statement_delta = failing_statements.count
      details = scope_details(transition_check, representative_webpages).merge(
        source: "statement_refresh",
        statements_refreshed_count: statements_scope.count,
        statements_failed_count: [statement_delta, reported_failing_statements.count].max,
        failing_statement_ids: reported_failing_statements.map(&:id),
        failing_statements: failing_statement_details(reported_failing_statements)
      )

      if refresh_errors.present?
        status = :failed
        details[:reason] = "statement_refresh_failed"
        details[:refresh_errors] = compact_refresh_errors(refresh_errors)
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
        url: cache_or_seed_url(latest_cache),
        check_kind: :statement_delta,
        status: :failed,
        statement_count_delta_acceptable: false,
        details: failure_details("statement_refresh_failed", error)
      )
    end

    def record_export_check(transition_check, representative_webpages)
      latest_cache = transition_check.cache
      return record_missing_representatives(latest_cache, :export_diff, transition_check) if representative_webpages.blank?

      if transition_check.fetch == :failed
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
            reason: "export_diff_not_available"
          )
        )
      end

      normalized_actual = Distillator::ExportNormalizer.normalize(actual)
      normalized_expected = Distillator::ExportNormalizer.normalize(expected)
      diff = Distillator::GraphDiff.call(expected_graph: normalized_expected, actual_graph: normalized_actual)
      failed = diff.added_count.positive? || diff.removed_count.positive? || diff.changed_literal_values.any? || diff.changed_uri_objects.any?
      status = failed ? :failed : :checked

      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        url: cache_or_seed_url(latest_cache),
        check_kind: :export_diff,
        status: status,
        export_diff_checked: status == :checked,
        export_diff_status: status.to_s,
        export_diff_accepted: false,
        rdf_added_count: diff.added_count,
        rdf_removed_count: diff.removed_count,
        details: scope_details(transition_check, representative_webpages).merge(
          source: "export_comparison",
          export_compared: true,
          export_basis: "current export vs production-equivalent export",
          changed_literal_values: diff.changed_literal_values.first(10),
          changed_uri_objects: diff.changed_uri_objects.first(10)
        )
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

    def fetch_check_payload(transition_check)
      cache = transition_check.cache
      representative_webpages = Array(transition_check.representative_webpages)
      details = scope_details(transition_check, representative_webpages).merge(
        source: "transition_check",
        attempted_condenser_fetch: transition_check.attempted_condenser_fetch == true,
        condenser_fetch_success: condenser_fetch_success?(transition_check),
        comparison_performed: transition_check.comparison.present?,
        comparison_policy: transition_check.comparison_policy.to_s,
        legacy_source: transition_check.comparison&.dig(:legacy_source),
        legacy_lookup_status: transition_check.comparison&.dig(:legacy_lookup_status),
        legacy_lookup_error: transition_check.comparison&.dig(:legacy_lookup_error),
        condenser_source: transition_check.comparison&.dig(:condenser_source),
        compare_missing: transition_check.comparison&.dig(:missing),
        compare_summary: transition_check.comparison&.dig(:summary),
        representative_urls_checked: transition_check.attempted_condenser_fetch == true
      ).compact

      unless representative_webpages.present?
        return [:pending, details.merge(reason: "no_representative_webpages", representative_urls_checked: false)]
      end

      unless cache.present?
        return [:failed, details.merge(reason: "missing_cache")]
      end

      if transition_check.fetch == :failed
        return [:failed, details.merge(reason: fetch_failure_reason(transition_check))]
      end

      comparison = transition_check.comparison
      if comparison.present? && comparison[:legacy_lookup_status] == "missing_config"
        return [:checked, details.merge(reason: "legacy_lookup_missing_config", comparison_performed: false)]
      end

      if comparison.present? && comparison[:legacy_lookup_status] == "unreachable"
        return [:checked, details.merge(reason: "legacy_lookup_unreachable", comparison_performed: false)]
      end

      if comparison.present? && comparison[:legacy_lookup_status] == "body_omitted"
        return [:checked, details.merge(reason: "legacy_lookup_body_omitted", comparison_performed: false)]
      end

      if comparison.present? && comparison.dig(:summary, :review_needed_diffs).present?
        return [:checked, details.merge(reason: "review_needed_difference")]
      end

      if comparison.present? &&
         comparison.dig(:summary, :metadata_only_diffs).present? &&
         comparison.dig(:summary, :blocking_regressions).blank? &&
         comparison.dig(:summary, :review_needed_diffs).blank? &&
         comparison.dig(:summary, :unknown_diffs).blank?
        return [:checked, details.merge(reason: "metadata_only_difference")]
      end

      if comparison.present? && (comparison.dig(:missing, :legacy) || comparison.dig(:missing, :condenser))
        return [:failed, details.merge(reason: "cache_compare_missing")]
      end

      if comparison.present? && comparison.dig(:summary, :blocking_regressions).present?
        return [:failed, details.merge(reason: "cache_compare_blocking_regression")]
      end

      [:checked, details]
    end

    def cache_or_seed_url(cache)
      cache&.normalized_url.presence || website.webpages.first&.url.presence || website.seedurl
    end

    def fetch_failure_reason(transition_check)
      result = transition_check.condenser_fetch_result
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

    def condenser_fetch_success?(transition_check)
      result = transition_check.condenser_fetch_result
      return false unless result.present?

      result.transport_success? && result.content_success?
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
  end
end
