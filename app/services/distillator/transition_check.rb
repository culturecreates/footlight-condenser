module Distillator
  class TransitionCheck
    SELECTION_RULE = "Event pages first, ordered by archive date".freeze

    Result = Struct.new(
      :website_id,
      :website,
      :mode,
      :priority,
      :active_backend,
      :latest_cache_status,
      :cache_present,
      :compare_available,
      :blocking_issues,
      :warnings,
      :promotable,
      :status,
      :fetch,
      :statements,
      :export,
      :representative_webpages,
      :representative_webpage_count,
      :candidate_webpage_count,
      :selection_rule,
      :cache,
      :cache_link_payload,
      :primary_action,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(website:, cache: nil, evidence_by_kind: nil)
      @website = website.is_a?(Website) ? website : Website.find(website)
      @cache = cache
      @evidence_by_kind = evidence_by_kind
    end

    def call
      Result.new(
        website_id: website.id,
        website: website,
        mode: website.distillator_mode.to_sym,
        priority: website.lavitrine_pipeline?,
        active_backend: rollout_resolution.active_backend,
        latest_cache_status: cache&.health_status.to_s.presence || "unknown",
        cache_present: cache.present?,
        compare_available: compare_available?,
        blocking_issues: transition_status.blockers,
        warnings: transition_status.warnings,
        promotable: transition_status.status == :ready,
        status: transition_status.status,
        fetch: transition_status.fetch,
        statements: transition_status.statements,
        export: transition_status.export,
        representative_webpages: representative_webpages,
        representative_webpage_count: representative_webpages.count,
        candidate_webpage_count: candidate_webpage_count,
        selection_rule: SELECTION_RULE,
        cache: cache,
        cache_link_payload: cache_link_payload,
        primary_action: primary_action
      )
    end

    private

    attr_reader :website, :evidence_by_kind

    def cache
      @cache ||= Distillator::ShadowReportQuery.latest_cache_for_website(website)
    end

    def transition_status
      @transition_status ||= Distillator::TransitionStatus.call(
        website: website,
        cache: cache,
        evidence_by_kind: evidence_by_kind || website.latest_transition_evidences_by_kind
      )
    end

    def rollout_resolution
      @rollout_resolution ||= Distillator::FetchMode.rollout_resolution_object(website: website)
    end

    def cache_link_payload
      @cache_link_payload ||= begin
        url = cache&.normalized_url.presence || website.webpages.first&.url.presence || website.seedurl
        Distillator::CacheLinkResolver.call(url: url, website: website)
      end
    end

    def compare_available?
      Array(cache_link_payload[:secondary_links]).any? do |link|
        link[:label] == Distillator::RolloutCopy.compare_label && link[:url].present?
      end
    end

    def primary_action
      Distillator::OperatorNextAction.call(
        website: website,
        transition_status: transition_status,
        cache_link_payload: cache_link_payload
      )
    end

    def representative_webpages
      representative_scope.limit(3).to_a
    end

    def candidate_webpage_count
      representative_scope.count
    end

    def representative_scope
      event_scope = website.webpages.event_pages.transition_candidates
      return event_scope if event_scope.exists?

      website.webpages.transition_candidates
    end
  end
end
