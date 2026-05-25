module Distillator
  class ShadowSiteDetail
    Result = Struct.new(
      :summary,
      :transition_status,
      :transition_evidence_by_kind,
      :transition_evidence_explanations,
      :primary_blocker,
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
        primary_blocker: primary_blocker,
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

        {
          representative_webpage_count: representative_count,
          candidate_webpage_count: candidate_count,
          representative_webpages: representative_urls,
          selection_rule: statement_details["selection_rule"] || export_details["selection_rule"] || fetch_details["selection_rule"] || Distillator::TransitionCheck::SELECTION_RULE,
          selected_candidate_tier_count: (statement_details["selected_candidate_tier_count"] || export_details["selected_candidate_tier_count"] || fetch_details["selected_candidate_tier_count"]).to_i,
          statements_refreshed_count: (statement_details["statements_refreshed_count"] || 0).to_i,
          statements_failed_count: (statement_details["statements_failed_count"] || transition_evidence_by_kind["statement_delta"]&.statement_delta || 0).to_i,
          export_compared: export_details["export_compared"] == true,
          export_basis: export_details["export_basis"].presence || "current export vs production-equivalent export",
          sample_small: (statement_details["sample_small"] == true || export_details["sample_small"] == true || fetch_details["sample_small"] == true || candidate_count > representative_count)
        }
      end
    end

    def primary_blocker
      @primary_blocker ||= transition_evidence_explanations.find { |explanation| explanation.severity == "blocker" && explanation.state != "passed" }
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

      ["All transition checks are currently passing."]
    end
  end
end
