module Distillator
  # Presentation of one immutable completed comparison, alongside explicitly
  # separate current operation/readiness. Never fetches or authorizes activation.
  class TransitionReportPresentation
    attr_reader :detail, :historical

    def initialize(detail:, historical: false)
      @detail = detail
      @historical = historical
    end

    def completed_status
      detail.completed_transition_status
    end

    def checks
      [
        { key: "fetch_parity", label: "Fresh fetch parity", state: fetch_state },
        { key: "statement_delta", label: "Statement equivalence", state: completed_status&.statements || :missing },
        { key: "export_diff", label: "Export serializer compatibility", state: completed_status&.export || :missing }
      ]
    end

    def fetch_state
      return :failed if detail.fetch_summary.issues.any? { |issue| issue[:backend] != "Transition check" }
      return :inconclusive if detail.fetch_summary.issues.any?

      completed_status&.fetch || :missing
    end

    def self.state_label(state)
      { passed: "Passed", warning: "Review required", failed: "Failed", inconclusive: "Incomplete",
        not_evaluated: "Not evaluated", blocked_by_fetch: "Not evaluated — fetch unavailable",
        stale: "Stale", missing: "Not recorded" }.fetch(state.to_sym, "Not evaluated")
    end

    def self.tone(state)
      { passed: "passed", warning: "review", failed: "failed", inconclusive: "review", stale: "review" }
        .fetch(state.to_sym, "neutral")
    end

    def field_findings
      @field_findings ||= begin
        data = detail.transition_evidence_by_kind["statement_delta"]&.details.to_h.with_indifferent_access
        Array(data&.[](:statement_artifacts)).map { |entry| entry.to_h.with_indifferent_access }
          .reject { |entry| entry[:verdict] == MigrationComparator::MATCH }
      end
    end

    def blocked_fields?
      field_findings.any? { |entry| finding_state(entry) == :failed } ||
        completed_status&.statements == :failed || completed_status&.export == :failed
    end

    def finding_state(entry)
      unsupported = [entry[:legacy_error], entry[:condenser_error]].compact.any? do |error|
        error.to_h.with_indifferent_access[:error_type].to_s.include?("FetchUnsupported")
      end
      return :inconclusive if unsupported

      entry[:severity] == "blocker" ? :failed : :warning
    end

    def incomplete?
      detail.fetch_summary.issues.any? || checks.any? do |check|
        check[:state].in?(%i[missing stale inconclusive not_evaluated blocked_by_fetch])
      end
    end

    def mode
      detail.summary.website.distillator_mode
    end

    def configuration_changed?
      detail.transition_status.blockers.include?("Source configuration changed since the last check. Run a new check.")
    end

    def no_eligible_pages?
      detail.checked_scope[:transition_exclusions].present? && detail.checked_scope[:representative_webpage_count].to_i.zero?
    end

    def decision_title
      return "Historical comparison: #{comparison_label}" if historical
      return "Active on Condenser" if mode == "active"
      return "Legacy Wringer active" if mode == "legacy"
      return "Check in progress — stay in Shadow" if detail.pending_transition_batch_check
      return "Latest check failed — stay in Shadow" if detail.transition_run_status == "failed"
      return "Run checks before activating" unless completed_status
      return "Scope or configuration changed — run a new check" if configuration_changed?
      return "No eligible pages remain — stay in Shadow" if no_eligible_pages?
      return "Blocked — stay in Shadow" if blocked_fields?
      return "Incomplete evidence — stay in Shadow" if incomplete?
      return "Blocked — stay in Shadow" if detail.transition_status.status == :blocked
      return "Review before activating" if detail.transition_status.status == :review
      if detail.transition_status.status == :ready
        return detail.checked_scope[:transition_exclusions].present? ? "Ready to activate — with reviewed exclusions" : "Ready to activate"
      end

      "Run checks before activating"
    end

    def decision_tone
      return "neutral" if historical || mode != "shadow"
      return "running" if detail.pending_transition_batch_check
      return "neutral" unless completed_status || detail.transition_run_status == "failed"
      return "review" if configuration_changed?
      return "failed" if detail.transition_run_status == "failed" || blocked_fields?
      return "review" if incomplete?

      { ready: "passed", review: "review", blocked: "failed" }.fetch(detail.transition_status.status, "neutral")
    end

    def comparison_label
      return "Not recorded" unless completed_status
      return "Accepted after review" if detail.operation_status.reviewed_completed_comparison?
      return "Blocking failures" if blocked_fields?
      return "Incomplete" if incomplete?
      return "Blocking failures" if completed_status.fetch == :failed

      { ready: "Passed", review: "Review required", blocked: "Blocked" }.fetch(completed_status.status, "Not checked")
    end

    def decision_reason
      return "Results from completed run ##{detail.completed_transition_run_id}; this is not current activation guidance." if historical
      return "Wringer serves this website. Move to Shadow before considering activation." if mode == "legacy"
      return detail.decision[:why].first if mode != "shadow"
      if detail.pending_transition_batch_check
        return detail.completed_transition_run_id ? "A new check is running. The results below still belong to the previous completed run." :
          "A check is running. Results will appear when all phases finish."
      end
      return detail.transition_run_error if detail.transition_run_status == "failed"
      return "Run a fresh comparison before considering activation." unless completed_status
      return "The completed comparison is unchanged. A new check must verify the current scope and configuration." if configuration_changed?
      return "All eligible candidates were excluded after review. An empty comparison cannot establish parity." if no_eligible_pages?
      return "Selected-field or export failures were recorded. Inspect the evidence below." if blocked_fields?
      if detail.fetch_summary.issues.any?
        count = detail.fetch_summary.issues.map { |issue| issue[:url] }.uniq.length
        return "Fresh HTML is unavailable for #{count} of #{detail.fetch_summary.selected} selected URLs. The affected backend and error are below."
      end

      detail.transition_status.primary_blocker.presence || detail.decision[:why].first
    end

    def next_action
      return if historical
      return "Follow the running check and wait for its completed result." if detail.pending_transition_batch_check
      return detail.decision[:recommended_action] if mode != "shadow"
      return "Inspect the failed attempt, then run a new check." if detail.transition_run_status == "failed"
      return "Run a new check with the reviewed exclusions applied to its scope." if configuration_changed?
      return "Restore at least one URL to transition scope before running another check." if no_eligible_pages?
      return "Compare the recorded values and errors below, then fix the affected selected sources." if field_findings.any?
      return detail.fetch_summary.issues.first[:action] if detail.fetch_summary.issues.any?

      detail.decision[:recommended_action]
    end

    def fetch_rows
      @fetch_rows ||= Array(detail.transition_evidence_by_kind["fetch_parity"]&.details.to_h["representative_url_results"])
        .map { |entry| entry.to_h.with_indifferent_access }
    end

    def unverified_pages
      @unverified_pages ||= Array(detail.transition_evidence_by_kind["statement_delta"]&.details.to_h["representative_url_statement_results"])
        .map { |entry| entry.to_h.with_indifferent_access }
        .select { |entry| entry[:status].in?(%w[inconclusive blocked_by_fetch]) }
    end
  end
end
