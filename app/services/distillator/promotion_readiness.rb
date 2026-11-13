module Distillator
  class PromotionReadiness
    EVIDENCE_STALE_AFTER = 72.hours
    LAVITRINE_EVIDENCE_STALE_AFTER = 24.hours
    EXPORT_DIFF_STALE_AFTER = 7.days

    Result = Struct.new(
      :blockers,
      :warnings,
      :evidence_by_kind,
      :safety,
      :confidence,
      :review_activation_eligible,
      :manual_review_required,
      :review_needed_fields,
      :comparison_policy,
      keyword_init: true
    )

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
      transition = transition_status
      Result.new(
        blockers: transition.blockers,
        warnings: transition.warnings,
        evidence_by_kind: evidence_by_kind,
        safety: transition.safety,
        confidence: transition.confidence,
        review_activation_eligible: transition.review_activation_eligible,
        manual_review_required: transition.manual_review_required,
        review_needed_fields: transition.review_needed_fields,
        comparison_policy: transition.comparison_policy
      )
    end

    private

    attr_reader :website, :cache, :now

    def evidence_by_kind
      @evidence_by_kind ||= website.respond_to?(:latest_transition_evidences_by_kind) ? website.latest_transition_evidences_by_kind : {}
    end

    def transition_status
      @transition_status ||= Distillator::TransitionStatus.call(
        website: website,
        cache: cache,
        evidence_by_kind: evidence_by_kind,
        now: now
      )
    end
  end
end
