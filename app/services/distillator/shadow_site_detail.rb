module Distillator
  class ShadowSiteDetail
    Result = Struct.new(
      :summary,
      :transition_status,
      :transition_evidence_by_kind,
      :transition_evidence_explanations,
      :latest_transition_evidence_checked_at,
      :transition_check_requested_at,
      :pending_transition_batch_check,
      :primary_blocker,
      :statement_failure_groups,
      :url_matrix,
      :root_cause,
      :checked_scope,
      :decision,
      :rollout_notes,
      :recent_rollout_events,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(website:, cache: nil)
      @website = website
      @cache = cache
    end

    def call
      Result.new(
        summary: summary,
        transition_status: transition_status,
        transition_evidence_by_kind: transition_evidence_by_kind,
        transition_evidence_explanations: transition_evidence_explanations,
        latest_transition_evidence_checked_at: website.latest_transition_evidence_checked_at,
        transition_check_requested_at: website.transition_check_requested_at,
        pending_transition_batch_check: website.pending_transition_batch_check?,
        primary_blocker: primary_blocker,
        statement_failure_groups: statement_failure_groups,
        url_matrix: url_matrix,
        root_cause: root_cause,
        checked_scope: checked_scope,
        decision: decision,
        rollout_notes: rollout_notes,
        recent_rollout_events: website.rollout_events.order(created_at: :desc).limit(5)
      )
    end

    private

    attr_reader :website, :cache

    def summary
      @summary ||= Distillator::ShadowSiteSummary.call(website: website, cache: resolved_cache, include_cache_links: true)
    end

    def transition_status
      @transition_status ||= Distillator::TransitionStatus.call(
        website: website,
        cache: resolved_cache,
        evidence_by_kind: transition_evidence_by_kind
      )
    end

    def transition_evidence_by_kind
      @transition_evidence_by_kind ||= website.latest_transition_evidences_by_kind
    end

    def transition_evidence_explanations
      @transition_evidence_explanations ||= transition_status.checks.map do |check|
        Distillator::TransitionEvidenceExplanation.call(
          check_kind: check.fetch(:key),
          evidence: transition_evidence_by_kind[check.fetch(:key)],
          website: website,
          state: check.fetch(:state)
        )
      end
    end

    def checked_scope
      @checked_scope ||= begin
        fetch_details = transition_evidence_by_kind["fetch_parity"]&.details.to_h || {}
        statement_details = transition_evidence_by_kind["statement_delta"]&.details.to_h || {}
        export_details = transition_evidence_by_kind["export_diff"]&.details.to_h || {}
        representative_urls = Array(statement_details["representative_webpages"] || export_details["representative_webpages"] || fetch_details["representative_webpages"]).compact
        representative_count = (statement_details["representative_webpage_count"] || export_details["representative_webpage_count"] || fetch_details["representative_webpage_count"] || representative_urls.count).to_i
        candidate_count = (statement_details["candidate_webpage_count"] || export_details["candidate_webpage_count"] || fetch_details["candidate_webpage_count"] || representative_count).to_i
        publishable_count = (statement_details["publishable_event_page_count"] || export_details["publishable_event_page_count"] || fetch_details["publishable_event_page_count"] || 0).to_i

        {
          representative_webpage_count: representative_count,
          candidate_webpage_count: candidate_count,
          publishable_event_page_count: publishable_count,
          representative_webpages: representative_urls,
          selection_rule: statement_details["selection_rule"] || export_details["selection_rule"] || fetch_details["selection_rule"] || Distillator::TransitionCheck::SELECTION_RULE,
          selected_candidate_tier_count: (statement_details["selected_candidate_tier_count"] || export_details["selected_candidate_tier_count"] || fetch_details["selected_candidate_tier_count"]).to_i,
          statements_refreshed_count: (statement_details["statements_refreshed_count"] || 0).to_i,
          statements_failed_count: (statement_details["statements_failed_count"] || transition_evidence_by_kind["statement_delta"]&.statement_delta || 0).to_i,
          critical_statements_failed_count: integer_detail(statement_details, "critical_statements_failed_count"),
          optional_statements_failed_count: integer_detail(statement_details, "optional_statements_failed_count"),
          legacy_statement_failure: legacy_statement_failure_details?(statement_details),
          statement_failure_reason: statement_details["reason"] || statement_details[:reason],
          export_compared: export_details["export_compared"] == true,
          export_basis: export_details["export_basis"].presence || "current export vs production-equivalent export",
          sample_small: (
            statement_details["sample_small"] == true ||
            export_details["sample_small"] == true ||
            fetch_details["sample_small"] == true ||
            (publishable_count.positive? ? publishable_count : candidate_count) > representative_count
          )
        }
      end
    end

    def url_matrix
      @url_matrix ||= begin
        fetch_rows = Array(transition_evidence_by_kind["fetch_parity"]&.details.to_h&.[]("representative_url_results") ||
          transition_evidence_by_kind["fetch_parity"]&.details.to_h&.[](:representative_url_results))
        statement_rows = Array(transition_evidence_by_kind["statement_delta"]&.details.to_h&.[]("representative_url_statement_results") ||
          transition_evidence_by_kind["statement_delta"]&.details.to_h&.[](:representative_url_statement_results))
        export_rows = Array(transition_evidence_by_kind["export_diff"]&.details.to_h&.[]("representative_url_export_results") ||
          transition_evidence_by_kind["export_diff"]&.details.to_h&.[](:representative_url_export_results))
        urls = checked_scope[:representative_webpages]
        urls.map do |url|
          fetch_row = symbolize_row(fetch_rows.find { |row| symbolize_row(row)[:url] == url })
          fetch_row = fallback_fetch_row(url) if fetch_row.blank?
          statement_row = symbolize_row(statement_rows.find { |row| symbolize_row(row)[:url] == url })
          statement_row = fallback_statement_row(url) if statement_row.blank?
          export_row = symbolize_row(export_rows.find { |row| symbolize_row(row)[:url] == url })
          export_row = fallback_export_row(url) if export_row.blank?
          {
            url: url,
            webpage_id: fetch_row[:webpage_id],
            condenser_fetch_result: condenser_fetch_label(fetch_row),
            legacy_lookup_result: legacy_lookup_label(fetch_row),
            cache_comparison_result: cache_comparison_label(fetch_row),
            statement_check_result: statement_check_label(statement_row),
            export_impact: export_impact_label(export_row),
            fetch_reason: fetch_row[:fetch_reason],
            legacy_lookup_reason: fetch_row[:legacy_lookup_error] || fetch_row[:legacy_lookup_status],
            cache_compare_reason: cache_compare_reason(fetch_row),
            statement_reason: statement_row[:reason],
            export_reason: export_row[:reason]
          }
        end
      end
    end

    def root_cause
      @root_cause ||= begin
        fetch_rows = url_matrix.select do |row|
          row[:fetch_reason].present? &&
            row[:fetch_reason] != "ok" &&
            row[:condenser_fetch_result] != "Passed"
        end
        legacy_rows = url_matrix.select { |row| row[:legacy_lookup_result] != "OK" }
        compare_rows = url_matrix.select { |row| row[:cache_comparison_result].in?(%w[Failed Review Unknown Missing]) }

        if primary_blocker&.key == "statement_delta"
          {
            failed_layer: "statements",
            concrete_reason: primary_blocker.headline,
            affected_url_count: checked_scope[:representative_webpage_count],
            next_operator_action: transition_status.primary_action
          }
        elsif primary_blocker&.key == "export_diff"
          {
            failed_layer: "export",
            concrete_reason: primary_blocker.headline,
            affected_url_count: checked_scope[:representative_webpage_count],
            next_operator_action: transition_status.primary_action
          }
        elsif fetch_rows.any?
          {
            failed_layer: "fetch",
            concrete_reason: fetch_rows.first[:fetch_reason].to_s.humanize,
            affected_url_count: fetch_rows.count,
            next_operator_action: "Fetch or refresh Condenser cache for the affected URLs, then rerun the transition batch check."
          }
        elsif legacy_rows.any?
          {
            failed_layer: "legacy lookup",
            concrete_reason: legacy_rows.first[:legacy_lookup_reason].to_s.humanize,
            affected_url_count: legacy_rows.count,
            next_operator_action: "Open the active Wringer cache or fix the legacy lookup configuration before rerunning the transition batch check."
          }
        elsif compare_rows.any?
          {
            failed_layer: "cache compare",
            concrete_reason: compare_rows.first[:cache_compare_reason].to_s.humanize,
            affected_url_count: compare_rows.count,
            next_operator_action: "Compare Condenser vs Wringer for the affected URLs and review the parity differences."
          }
        else
          {
            failed_layer: "evidence missing",
            concrete_reason: "No failing layer is currently recorded for the sampled URLs.",
            affected_url_count: 0,
            next_operator_action: transition_status.primary_action
          }
        end
      end
    end

    def primary_blocker
      @primary_blocker ||= transition_evidence_explanations.find { |explanation| explanation.severity == "blocker" && explanation.state != "passed" }
    end

    def statement_failure_groups
      @statement_failure_groups ||= begin
        details = transition_evidence_by_kind["statement_delta"]&.details.to_h || {}
        failing_statements = statement_failure_entries(details)
        statements_failed_count = (details["statements_failed_count"] || details[:statements_failed_count] || 0).to_i
        reasons = Array(details["refresh_errors"] || details[:refresh_errors]).map(&:to_s)
        normalized_reason = normalize_statement_failure_reason(reasons.first.presence || details["reason"] || details[:reason])

        grouped = failing_statements.group_by do |statement|
          [
            statement[:severity].presence || "blocker",
            normalized_reason,
            statement[:source].presence || "Unknown source"
          ]
        end.map do |(severity, reason, source), entries|
          {
            severity: severity.presence || entries.first[:severity].presence || "blocker",
            reason: reason,
            source: source,
            count: entries.count,
            statement_ids: entries.map { |entry| entry[:id] }.compact
          }
        end

        if grouped.blank? && statements_failed_count.positive?
          grouped = [{
            severity: legacy_statement_failure_details?(details) ? "unknown" : (details["optional_statements_failed_count"].to_i.positive? && details["critical_statements_failed_count"].to_i.zero? ? "warning" : "blocker"),
            reason: normalized_reason,
            source: nil,
            count: statements_failed_count,
            statement_ids: []
          }]
        end

        grouped.sort_by { |group| [group[:severity] == "blocker" ? 0 : 1, -group[:count].to_i, group[:reason].to_s, group[:source].to_s] }
      end
    end

    def decision
      @decision ||= begin
        action = if primary_blocker.present?
          primary_blocker.next_action
        elsif transition_status.review_activation_eligible
          "Use the review checklist, then activate with a recorded reason if the content is acceptable."
        elsif transition_status.status == :ready
          "Promote to active when you are satisfied with the evidence."
        else
          transition_status.primary_action
        end

        {
          label: decision_label,
          why: decision_reasons,
          evidence: transition_status.checks.map do |check|
            {
              label: check.fetch(:label),
              state: check.fetch(:state),
              checked_at: transition_evidence_by_kind[check.fetch(:key)]&.checked_at
            }
          end,
          recommended_action: action
        }
      end
    end

    def resolved_cache
      @resolved_cache ||= cache || Distillator::ShadowReportQuery.latest_cache_for_website(website)
    end

    def rollout_notes
      notes = [Distillator::RolloutCopy.description(website.distillator_mode)]
      if website.lavitrine_pipeline?
        notes << "La Vitrine pipeline requires all three checks before activation: Fetch, Statements, and Export."
      else
        notes << "Fetch, Statements, and Export checks should be reviewed before activation."
      end
      notes
    end

    def decision_label
      case transition_status.status
      when :blocked
        "Do not activate yet"
      when :review
        "Review before activating"
      when :ready
        "Safe to promote"
      else
        "Run checks before activating"
      end
    end

    def decision_reasons
      return [primary_blocker.headline] if primary_blocker.present?
      return transition_status.warnings.presence if transition_status.warnings.any?

      ["All sampled transition checks are currently passing."]
    end

    def symbolize_row(row)
      row.respond_to?(:to_h) ? row.to_h.symbolize_keys : {}
    end

    def condenser_fetch_label(row)
      return "Missing" if row.blank?
      if row[:fetch_status] == "failed"
        return "Captcha" if row[:fetch_reason] == "captcha_detected"
        return "Renderer unavailable" if %w[renderer_unavailable phantomjs_api_key_missing].include?(row[:fetch_reason].to_s)
        return "Timed out" if row[:fetch_reason] == "transition_check_timeout_budget_exceeded"
        return "Redirected" if row[:fetch_reason] == "redirect_to_listing"

        return "Failed"
      end

      "Passed"
    end

    def legacy_lookup_label(row)
      status = row[:legacy_lookup_status].to_s
      return "OK" if status.blank? || status == "ok"
      return "Missing config" if status == "missing_config"
      return "Unreachable" if status == "unreachable"
      return "Body omitted" if status == "body_omitted"

      status.humanize
    end

    def cache_comparison_label(row)
      case row[:comparison_status].to_s
      when "passed", ""
        "Passed"
      when "metadata_only"
        "Passed with metadata notes"
      when "review"
        "Review"
      when "unknown", "not_performed"
        "Unknown"
      when "missing"
        "Missing"
      else
        "Failed"
      end
    end

    def statement_check_label(row)
      case row[:status].to_s
      when "passed"
        "Passed"
      when "warning"
        "Warning"
      when "failed"
        "Failed"
      when "blocked_by_fetch"
        "Blocked by fetch"
      when "inconclusive"
        "Inconclusive"
      else
        transition_status.statements.to_s.humanize
      end
    end

    def export_impact_label(row)
      case row[:status].to_s
      when "checked"
        "Passed"
      when "failed"
        "Failed"
      when "blocked_by_fetch"
        "Blocked by fetch"
      when "inconclusive"
        "Inconclusive"
      else
        transition_status.export.to_s.humanize
      end
    end

    def normalize_statement_failure_reason(raw_reason)
      reason = raw_reason.to_s.strip
      return "Statement failure" if reason.blank?
      return "Blank DSL result" if reason.match?(/blank/i)
      return "Captcha during URL step" if reason.match?(/captcha/i)
      return "Invalid URL from json_url" if reason.match?(/invalid url/i) || reason.match?(/json_url/i)
      return "Optional statement warning" if reason == "optional_statement_refresh_warning"
      return "Critical statement failure" if reason.in?(%w[critical_statement_refresh_failed critical_and_optional_statement_refresh_failed])

      reason.sub(/\AReason:\s*/i, "").strip.humanize
    end

    def statement_failure_entries(details)
      explicit = []
      explicit.concat(Array(details["critical_failing_statements"] || details[:critical_failing_statements]).map do |entry|
        normalize_statement_failure_entry(entry, "blocker")
      end)
      explicit.concat(Array(details["optional_failing_statements"] || details[:optional_failing_statements]).map do |entry|
        normalize_statement_failure_entry(entry, "warning")
      end)
      return explicit if explicit.any?

      default_severity = legacy_statement_failure_details?(details) ? "unknown" : nil
      Array(details["failing_statements"] || details[:failing_statements]).map do |entry|
        normalize_statement_failure_entry(entry, default_severity)
      end
    end

    def normalize_statement_failure_entry(entry, severity)
      hash = entry.respond_to?(:to_h) ? entry.to_h.symbolize_keys : {}
      hash[:severity] = severity.presence || hash[:severity].presence || "blocker"
      hash
    end

    def cache_compare_reason(row)
      return row[:comparison_status] if row[:comparison_status].present? && row[:comparison_status] != "passed"
      return "metadata_only_difference" if row[:comparison_status] == "metadata_only"

      "ok"
    end

    def fallback_fetch_row(url)
      details = transition_evidence_by_kind["fetch_parity"]&.details.to_h || {}
      {
        url: url,
        webpage_id: website.webpages.find_by(url: url)&.id,
        fetch_status: transition_status.fetch == :failed ? "failed" : "passed",
        fetch_reason: details["reason"] || details[:reason] || "ok",
        legacy_lookup_status: details["legacy_lookup_status"] || details[:legacy_lookup_status] || "ok",
        legacy_lookup_error: details["legacy_lookup_error"] || details[:legacy_lookup_error],
        comparison_status: fallback_comparison_status(details)
      }
    end

    def fallback_statement_row(url)
      details = transition_evidence_by_kind["statement_delta"]&.details.to_h || {}
      {
        url: url,
        status: case transition_status.statements
                when :passed then "passed"
                when :warning then "warning"
                when :failed then "failed"
                when :not_evaluated then "blocked_by_fetch"
                when :inconclusive then "inconclusive"
                else transition_status.statements.to_s
                end,
        reason: details["reason"] || details[:reason]
      }
    end

    def fallback_export_row(url)
      details = transition_evidence_by_kind["export_diff"]&.details.to_h || {}
      {
        url: url,
        status: case transition_status.export
                when :passed then "checked"
                when :failed then "failed"
                when :blocked_by_fetch then "blocked_by_fetch"
                when :inconclusive then "inconclusive"
                else transition_status.export.to_s
                end,
        reason: details["reason"] || details[:reason]
      }
    end

    def fallback_comparison_status(details)
      reason = details["reason"] || details[:reason]
      return "failed" if reason == "cache_compare_blocking_regression"
      return "missing" if reason == "cache_compare_missing"
      return "unknown" if reason == "cache_compare_unknown"
      return "review" if reason == "review_needed_difference"
      return "metadata_only" if reason == "metadata_only_difference"

      "passed"
    end

    def legacy_statement_failure_details?(details)
      return false unless (details["statements_failed_count"] || details[:statements_failed_count] || 0).to_i.positive?

      reason = details["reason"] || details[:reason]
      return false if reason.to_s.in?(%w[fetch_failed_before_statement_refresh partial_fetch_failed_before_statement_refresh transition_check_timeout_budget_exceeded no_selected_statements optional_statement_refresh_warning])

      !detail_key_present?(details, "critical_statements_failed_count") &&
        !detail_key_present?(details, "optional_statements_failed_count")
    end

    def integer_detail(details, key)
      return nil unless detail_key_present?(details, key)

      (details[key.to_s] || details[key.to_sym]).to_i
    end

    def detail_key_present?(details, key)
      details.key?(key.to_s) || details.key?(key.to_sym)
    end
  end
end
