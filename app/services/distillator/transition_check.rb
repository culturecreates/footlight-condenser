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
      :representative_webpage,
      :representative_webpages,
      :representative_url,
      :representative_webpage_count,
      :candidate_webpage_count,
      :selection_rule,
      :attempted_condenser_fetch,
      :condenser_fetch_result,
      :comparison,
      :cache,
      :cache_link_payload,
      :primary_action,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(
      website:,
      cache: nil,
      evidence_by_kind: nil,
      run_fetch: false,
      fetch_cache_store: Distillator::FetchCacheStore,
      cache_compare: Distillator::CacheCompare
    )
      @website = website.is_a?(Website) ? website : Website.find(website)
      @cache = cache
      @evidence_by_kind = evidence_by_kind
      @run_fetch = run_fetch == true
      @fetch_cache_store = fetch_cache_store
      @cache_compare = cache_compare
    end

    def call
      representative_webpages = representative_webpages()
      representative_webpage = representative_webpages.first
      fetch_attempt = fetch_attempt_for(representative_webpage)

      Result.new(
        website_id: website.id,
        website: website,
        mode: website.distillator_mode.to_sym,
        priority: website.lavitrine_pipeline?,
        active_backend: rollout_resolution.active_backend,
        latest_cache_status: resolved_cache&.health_status.to_s.presence || "unknown",
        cache_present: resolved_cache.present?,
        compare_available: compare_available?,
        blocking_issues: transition_status.blockers,
        warnings: transition_status.warnings,
        promotable: transition_status.status == :ready,
        status: transition_status.status,
        fetch: transition_status.fetch,
        statements: transition_status.statements,
        export: transition_status.export,
        representative_webpage: representative_webpage,
        representative_webpages: representative_webpages,
        representative_url: representative_webpage&.url,
        representative_webpage_count: representative_webpages.count,
        candidate_webpage_count: candidate_webpage_count,
        selection_rule: SELECTION_RULE,
        attempted_condenser_fetch: fetch_attempt[:attempted],
        condenser_fetch_result: fetch_attempt[:result],
        comparison: fetch_attempt[:comparison],
        cache: resolved_cache,
        cache_link_payload: cache_link_payload,
        primary_action: primary_action
      )
    end

    private

    attr_reader :website, :evidence_by_kind, :fetch_cache_store, :cache_compare

    def cache
      @cache ||= Distillator::ShadowReportQuery.latest_cache_for_website(website)
    end

    def resolved_cache
      @resolved_cache ||= cache
    end

    def transition_status
      @transition_status ||= Distillator::TransitionStatus.call(
        website: website,
        cache: resolved_cache,
        evidence_by_kind: evidence_by_kind || website.latest_transition_evidences_by_kind
      )
    end

    def rollout_resolution
      @rollout_resolution ||= Distillator::FetchMode.rollout_resolution_object(website: website)
    end

    def cache_link_payload
      @cache_link_payload ||= begin
        url = resolved_cache&.normalized_url.presence || website.webpages.first&.url.presence || website.seedurl
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

    def run_fetch?
      @run_fetch == true
    end

    def fetch_attempt_for(representative_webpage)
      return { attempted: false, result: nil, comparison: nil } unless run_fetch?
      return { attempted: false, result: nil, comparison: nil } unless representative_webpage.present?

      fetch_result = fetch_cache_store.fetch(
        uri: representative_webpage.url,
        force_scrape: true,
        mode: "shadow",
        website: website,
        log_context: {
          source: "transition_check",
          website_id: website.id,
          seedurl: website.seedurl
        }
      )

      @resolved_cache = fetch_result.cache || cache

      {
        attempted: true,
        result: fetch_result,
        comparison: cache_compare.call(uri: representative_webpage.url, condenser_result: fetch_result)
      }
    end
  end
end
