module Distillator
  class TransitionCheck
    PUBLISHABLE_SAMPLE_PERCENT = 0.20
    MINIMUM_PUBLISHABLE_SAMPLE_SIZE = 5
    MAXIMUM_PUBLISHABLE_SAMPLE_SIZE = 25
    FALLBACK_REPRESENTATIVE_SAMPLE_SIZE = 3
    SELECTION_RULE = "20% of publishable event pages, minimum 5, capped at 25, or all pages when fewer than 5 exist.".freeze

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
      :publishable_event_page_count,
      :selected_candidate_tier_count,
      :selection_rule,
      :attempted_condenser_fetch,
      :condenser_fetch_result,
      :comparison,
      :comparison_policy,
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
      comparison_policy: :operator,
      fetch_cache_store: Distillator::FetchCacheStore,
      cache_compare: Distillator::CacheCompare
    )
      @website = website.is_a?(Website) ? website : Website.find(website)
      @cache = cache
      @evidence_by_kind = evidence_by_kind
      @run_fetch = run_fetch == true
      @comparison_policy = normalize_comparison_policy(comparison_policy)
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
        publishable_event_page_count: publishable_event_page_count,
        selected_candidate_tier_count: selected_candidate_tier_count,
        selection_rule: SELECTION_RULE,
        attempted_condenser_fetch: fetch_attempt[:attempted],
        condenser_fetch_result: fetch_attempt[:result],
        comparison: fetch_attempt[:comparison],
        comparison_policy: comparison_policy,
        cache: resolved_cache,
        cache_link_payload: cache_link_payload,
        primary_action: primary_action
      )
    end

    private

    attr_reader :website, :evidence_by_kind, :fetch_cache_store, :cache_compare, :comparison_policy

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
      if publishable_event_page_count.positive?
        publishable_representative_webpages
      else
        generic_representative_scope.limit(FALLBACK_REPRESENTATIVE_SAMPLE_SIZE).to_a
      end
    end

    def candidate_webpage_count
      website.webpages.transition_candidates.count
    end

    def publishable_event_page_count
      @publishable_event_page_count ||= publishable_event_scope.count
    end

    def selected_candidate_tier_count
      publishable_event_page_count.positive? ? publishable_event_page_count : generic_representative_scope.count
    end

    def publishable_representative_webpages
      remaining = publishable_sample_size
      pages = []

      [future_publishable_event_scope, nil_archive_publishable_event_scope, past_publishable_event_scope].each do |scope|
        break if remaining <= 0

        selected = scope.limit(remaining).to_a
        pages.concat(selected)
        remaining -= selected.length
      end

      pages
    end

    def publishable_sample_size
      count = publishable_event_page_count
      return 0 if count.zero?

      [count, [[(count * PUBLISHABLE_SAMPLE_PERCENT).ceil, MINIMUM_PUBLISHABLE_SAMPLE_SIZE].max, MAXIMUM_PUBLISHABLE_SAMPLE_SIZE].min].min
    end

    def publishable_event_scope
      website.webpages.publishable.event_pages
    end

    def future_publishable_event_scope
      publishable_event_scope
        .where("archive_date >= ?", Time.current.beginning_of_day)
        .reorder(archive_date: :asc, updated_at: :desc, id: :asc)
    end

    def past_publishable_event_scope
      publishable_event_scope
        .where.not(archive_date: nil)
        .where("archive_date < ?", Time.current.beginning_of_day)
        .reorder(archive_date: :desc, updated_at: :desc, id: :asc)
    end

    def nil_archive_publishable_event_scope
      publishable_event_scope
        .where(archive_date: nil)
        .reorder(updated_at: :desc, created_at: :desc, id: :asc)
    end

    def generic_representative_scope
      website.webpages.reorder(updated_at: :desc, created_at: :desc, id: :asc)
    end

    def run_fetch?
      @run_fetch == true
    end

    def fetch_attempt_for(representative_webpage)
      return { attempted: false, result: nil, comparison: nil } unless run_fetch?
      return { attempted: false, result: nil, comparison: nil } unless representative_webpage.present?

      # Transition checks force fresh Condenser evidence through the internal-only path.
      # CacheCompare performs the separate legacy/Wringer lookup afterward.
      fetch_result = fetch_cache_store.fetch(
        uri: representative_webpage.url,
        force_scrape: true,
        mode: "internal",
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
        comparison: cache_compare.call(
          uri: representative_webpage.url,
          condenser_result: fetch_result,
          comparison_policy: comparison_policy
        )
      }
    end

    def normalize_comparison_policy(value)
      candidate = value.to_s.presence&.to_sym || :operator
      Distillator::CacheCompare::POLICIES.include?(candidate) ? candidate : :operator
    end
  end
end
