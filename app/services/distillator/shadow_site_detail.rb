module Distillator
  class ShadowSiteDetail
    Result = Struct.new(
      :summary,
      :transition_status,
      :transition_evidence_by_kind,
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
        transition_status: transition_check,
        transition_evidence_by_kind: website.latest_transition_evidences_by_kind,
        rollout_notes: rollout_notes,
        recent_rollout_events: website.rollout_events.order(created_at: :desc).limit(5)
      )
    end

    private

    attr_reader :website, :cache

    def summary
      @summary ||= Distillator::ShadowSiteSummary.call(website: website, cache: resolved_cache)
    end

    def transition_status
      @transition_status ||= Distillator::TransitionStatus.call(
        website: website,
        cache: resolved_cache,
        evidence_by_kind: website.latest_transition_evidences_by_kind
      )
    end

    def transition_check
      @transition_check ||= Distillator::TransitionCheck.call(
        website: website,
        cache: resolved_cache,
        evidence_by_kind: website.latest_transition_evidences_by_kind
      )
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
  end
end
