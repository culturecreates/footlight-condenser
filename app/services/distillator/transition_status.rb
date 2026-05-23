module Distillator
  class TransitionStatus
    CHECK_RESULTS = %i[passed failed missing stale not_evaluated blocked_by_fetch inconclusive].freeze
    STATUSES = %i[ready review blocked not_checked].freeze

    Result = Struct.new(
      :status,
      :fetch,
      :statements,
      :export,
      :checks,
      :activation_recommendation,
      :evidence_statuses,
      :blockers,
      :warnings,
      :last_checked,
      :readiness_label,
      :severity,
      :primary_blocker,
      :primary_action,
      keyword_init: true
    )

    READINESS_LABELS = {
      blocked: "Blocked",
      review: "Needs review",
      ready: "Ready",
      not_checked: "Not checked"
    }.freeze

    STATUS_SEVERITIES = {
      blocked: "high",
      review: "medium",
      ready: "ok",
      not_checked: "unknown"
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(website:, cache: nil, evidence_by_kind: nil, now: Time.current)
      @website = website
      @cache = cache
      @evidence_by_kind = evidence_by_kind
      @now = now
    end

    def call
      Result.new(
        status: overall_status,
        fetch: fetch_status,
        statements: statements_status,
        export: export_status,
        checks: checks,
        activation_recommendation: activation_recommendation,
        evidence_statuses: evidence_statuses,
        blockers: blockers,
        warnings: warnings,
        last_checked: last_checked,
        readiness_label: readiness_label,
        severity: severity,
        primary_blocker: primary_blocker,
        primary_action: primary_action
      )
    end

    def readiness_label
      READINESS_LABELS.fetch(overall_status, READINESS_LABELS.fetch(:not_checked))
    end

    def severity
      STATUS_SEVERITIES.fetch(overall_status, STATUS_SEVERITIES.fetch(:not_checked))
    end

    def primary_blocker
      primary_blocker_reason.presence || blockers.first || warnings.first
    end

    def primary_action
      activation_next_action
    end

    private

    attr_reader :website, :cache, :now

    def overall_status
      return :not_checked unless cache.present? || any_evidence_present?
      return :blocked if blockers.any?
      return :review if warnings.any?

      :ready
    end

    def blockers
      reasons = []
      reasons << "Cannot activate yet: fetch check failed." if fetch_status == :failed
      reasons << "Cannot activate yet: fetch check is stale." if fetch_status == :stale && lavitrine_pipeline?
      reasons << "Cannot activate yet: statements check failed." if statements_status == :failed
      reasons << "Cannot activate yet: statements could not be evaluated until fetch/cache is fixed." if statements_status == :not_evaluated && fetch_status != :failed
      reasons << "Cannot activate yet: statements check is inconclusive." if statements_status == :inconclusive
      reasons << "Cannot activate yet: statements check is missing." if lavitrine_pipeline? && statements_status == :missing
      reasons << "Cannot activate yet: statements check is stale." if lavitrine_pipeline? && statements_status == :stale
      reasons << "Cannot activate yet: export check failed." if export_status == :failed
      reasons << "Cannot activate yet: export comparison could not be evaluated until fetch/cache is fixed." if export_status == :blocked_by_fetch && fetch_status != :failed
      reasons << "Cannot activate yet: export check is inconclusive." if export_status == :inconclusive
      reasons << "Cannot activate yet: export check is missing." if lavitrine_pipeline? && export_status == :missing
      reasons << "Cannot activate yet: export check is stale." if lavitrine_pipeline? && export_status == :stale
      reasons.uniq
    end

    def warnings
      reasons = []
      reasons << legacy_lookup_warning if legacy_lookup_warning.present?
      reasons << "Needs review: fetch check is stale." if fetch_status == :stale && !lavitrine_pipeline?
      reasons << "Needs review: statements check is missing." if !lavitrine_pipeline? && statements_status == :missing
      reasons << "Needs review: statements check is stale." if !lavitrine_pipeline? && statements_status == :stale
      reasons << "Needs review: statements check is inconclusive." if !lavitrine_pipeline? && statements_status == :inconclusive
      reasons << "Needs review: export check is missing." if !lavitrine_pipeline? && export_status == :missing
      reasons << "Needs review: export check is stale." if !lavitrine_pipeline? && export_status == :stale
      reasons << "Needs review: export check is inconclusive." if !lavitrine_pipeline? && export_status == :inconclusive
      reasons << "Needs review: export check is stale." if export_status == :stale && export_diff_evidence&.export_diff_accepted?
      reasons << "Needs review: fetch result redirected." if redirect_changed?
      reasons << "Needs review: latest successful refresh is stale." if stale_successful_refresh?
      reasons.uniq
    end

    def fetch_status
      evidence = fetch_parity_evidence
      return fetch_status_from_evidence(evidence) if evidence.present?
      return :missing unless cache.present?
      return :failed if fetch_failed?
      return :stale if fetch_evidence_stale?

      :passed
    end

    def statements_status
      evidence = statement_delta_evidence
      return :missing if lavitrine_pipeline? && !evidence.present?
      return signal_status("statement_count_delta_acceptable") unless evidence.present?
      return :not_evaluated if fetch_prevented_statement_refresh?(evidence)
      return :inconclusive if no_selected_statements?(evidence)
      return :missing if evidence.status.to_s == "pending"
      return :failed if evidence.status.to_s.in?(%w[failed blocked rejected]) || evidence.acceptable_statement_delta? == false
      return :stale if evidence.checked_at < now - evidence_stale_after
      return :passed if evidence.acceptable_statement_delta?

      :missing
    end

    def export_status
      evidence = export_diff_evidence
      return :missing if lavitrine_pipeline? && !evidence.present?
      return export_status_from_cache unless evidence.present?
      return :blocked_by_fetch if fetch_prevented_export_comparison?(evidence)
      return :inconclusive if export_diff_not_available?(evidence)
      return :missing if evidence.status.to_s == "pending"
      return :failed if evidence.status.to_s.in?(%w[failed blocked rejected]) || explicit_false?(evidence.export_diff_checked)
      return :stale if export_evidence_stale?(evidence)
      return :passed if evidence.export_diff_satisfied?

      :missing
    end

    def signal_status(signal_key)
      value = signal(signal_key)
      return :missing if value.nil? || value.to_s == ""
      return :failed if explicit_false?(value)

      :passed
    end

    def fetch_status_from_evidence(evidence)
      return :missing if evidence.status.to_s == "pending"
      return :failed if evidence.status.to_s.in?(%w[failed blocked rejected])
      return :stale if evidence.checked_at < now - evidence_stale_after
      return :passed if evidence.status.to_s.in?(%w[checked accepted warning])

      :missing
    end

    def export_status_from_cache
      return :missing unless cache.present?

      status = signal("export_diff_status").to_s
      checked = signal("export_diff_checked")
      accepted = signal("export_diff_accepted")
      return :failed if %w[failed blocked rejected].include?(status)
      return :passed if truthy?(checked) || truthy?(accepted) || %w[checked accepted].include?(status)

      :missing
    end

    def fetch_failed?
      latest_attempt_failed? || transport_failed? || content_failed? || blocking_issue? || last_good_preserved_failure?
    end

    def latest_attempt_failed?
      %w[blocked network_failed attempt_failed content_rejected empty_body preserved_after_failure].include?(cache.health_status.to_s)
    end

    def transport_failed?
      explicit_false?(signal("transport_success")) || cache.network_status.to_s == "failed"
    end

    def content_failed?
      explicit_false?(signal("content_success"))
    end

    def blocking_issue?
      cache.primary_issue_severity.to_s.in?(%w[blocked failed])
    end

    def last_good_preserved_failure?
      truthy?(signal("last_good_preserved_failure"))
    end

    def fetch_evidence_stale?
      return false unless cache&.successful_refresh.present?

      cache.successful_refresh < now - evidence_stale_after
    end

    def stale_successful_refresh?
      fetch_evidence_stale?
    end

    def redirect_changed?
      return false unless cache.present?

      cache.redirected == true ||
        (cache.final_url.present? && cache.final_url.to_s != cache.normalized_url.to_s)
    end

    def export_evidence_stale?(evidence)
      threshold = evidence.export_diff_accepted? ? Distillator::PromotionReadiness::EXPORT_DIFF_STALE_AFTER : evidence_stale_after
      evidence.checked_at < now - threshold
    end

    def evidence_stale_after
      lavitrine_pipeline? ? Distillator::PromotionReadiness::LAVITRINE_EVIDENCE_STALE_AFTER : Distillator::PromotionReadiness::EVIDENCE_STALE_AFTER
    end

    def last_checked
      times = [cache&.scrape_date, cache&.successful_refresh]
      times.concat(evidence_by_kind.values.compact.map(&:checked_at))
      times.compact.max
    end

    def any_evidence_present?
      evidence_by_kind.values.any?(&:present?)
    end

    def evidence_statuses
      {
        "fetch_parity" => transition_evidence_status(fetch_parity_evidence),
        "statement_delta" => transition_evidence_status(statement_delta_evidence),
        "export_diff" => transition_evidence_status(export_diff_evidence)
      }
    end

    def checks
      [
        { key: "fetch_parity", label: "Fetch parity", state: fetch_status },
        { key: "statement_delta", label: "Statements", state: statements_status },
        { key: "export_diff", label: "Export", state: export_status }
      ]
    end

    def activation_recommendation
      {
        label: activation_label,
        reason: activation_reason,
        next_action: activation_next_action
      }
    end

    def activation_label
      readiness_label
    end

    def activation_reason
      return primary_blocker if primary_blocker.present?
      return "All transition checks are currently passing." if overall_status == :ready

      "Run the transition check to record current evidence."
    end

    def activation_next_action
      return "Fix fetch/cache first, then rerun the transition check." if fetch_status == :failed
      return "Configure the Wringer endpoint for staging, then rerun the transition check." if legacy_lookup_missing_config?
      return "Fix the legacy Wringer endpoint, then rerun the transition check." if legacy_lookup_unreachable?
      return "Verify selected sources/statements for the sampled webpages." if statements_status == :inconclusive
      return "Fix the blocking check, then rerun the transition check." if blockers.any?
      return "Review the warning and rerun the transition check if needed." if warnings.any?
      return "Promote to active when you are satisfied with the evidence." if overall_status == :ready

      "Run the transition check to record current evidence."
    end

    def transition_evidence_status(evidence)
      return :missing unless evidence.present?
      return :not_evaluated if fetch_prevented_statement_refresh?(evidence)
      return :blocked_by_fetch if fetch_prevented_export_comparison?(evidence)
      return :inconclusive if no_selected_statements?(evidence) || export_diff_not_available?(evidence)
      return :missing if evidence.status.to_s == "pending"
      return :failed if evidence.status.to_s.in?(%w[failed blocked rejected])
      return :stale if evidence.checked_at < now - evidence_stale_after

      :checked
    end

    def evidence_by_kind
      @evidence_by_kind ||= website.respond_to?(:latest_transition_evidences_by_kind) ? website.latest_transition_evidences_by_kind : {}
    end

    def fetch_parity_evidence
      evidence_by_kind["fetch_parity"]
    end

    def statement_delta_evidence
      evidence_by_kind["statement_delta"]
    end

    def export_diff_evidence
      evidence_by_kind["export_diff"]
    end

    def lavitrine_pipeline?
      website.respond_to?(:lavitrine_pipeline?) && website.lavitrine_pipeline?
    end

    def signal(key)
      return nil unless cache.present?

      signals = (cache.signals || {}).to_h
      return signals[key.to_s] if signals.key?(key.to_s)
      return signals[key.to_sym] if signals.key?(key.to_sym)

      nil
    end

    def truthy?(value)
      value == true || value.to_s == "true" || value.to_s == "1"
    end

    def explicit_false?(value)
      value == false || value.to_s == "false" || value.to_s == "0"
    end

    def legacy_lookup_warning
      return "Needs review: legacy Wringer endpoint is not configured for this environment." if legacy_lookup_missing_config?
      return "Needs review: legacy Wringer lookup failed during the latest transition check." if legacy_lookup_unreachable?

      nil
    end

    def legacy_lookup_missing_config?
      fetch_parity_evidence&.detail_reason == "legacy_lookup_missing_config"
    end

    def legacy_lookup_unreachable?
      fetch_parity_evidence&.detail_reason == "legacy_lookup_unreachable"
    end

    def primary_blocker_reason
      return "Cannot activate yet: fetch check failed." if fetch_status == :failed
      return "Cannot activate yet: fetch check is stale." if fetch_status == :stale && lavitrine_pipeline?
      return "Cannot activate yet: statements could not be evaluated until fetch/cache is fixed." if statements_status == :not_evaluated
      return "Cannot activate yet: statements check is inconclusive." if statements_status == :inconclusive
      return "Cannot activate yet: statements check failed." if statements_status == :failed
      return "Cannot activate yet: export comparison could not be evaluated until fetch/cache is fixed." if export_status == :blocked_by_fetch
      return "Cannot activate yet: export check is inconclusive." if export_status == :inconclusive
      return "Cannot activate yet: export check failed." if export_status == :failed
    end

    def evidence_reason(evidence)
      evidence&.details.to_h&.[]("reason") || evidence&.details.to_h&.[](:reason)
    end

    def fetch_prevented_statement_refresh?(evidence)
      evidence_reason(evidence) == "fetch_failed_before_statement_refresh"
    end

    def no_selected_statements?(evidence)
      evidence_reason(evidence) == "no_selected_statements"
    end

    def fetch_prevented_export_comparison?(evidence)
      evidence_reason(evidence) == "fetch_failed_before_export_comparison"
    end

    def export_diff_not_available?(evidence)
      evidence_reason(evidence) == "export_diff_not_available"
    end
  end
end
