module Distillator
  class TransitionCheck
    PUBLISHABLE_SAMPLE_PERCENT = 0.20
    MINIMUM_PUBLISHABLE_SAMPLE_SIZE = 5
    MAXIMUM_PUBLISHABLE_SAMPLE_SIZE = 25
    FALLBACK_REPRESENTATIVE_SAMPLE_SIZE = 3
    SELECTION_RULE = "20% of active publishable event pages with public URLs, minimum 5, capped at 25.".freeze

    def self.default_publishable_sample_size(count)
      [[(count * PUBLISHABLE_SAMPLE_PERCENT).ceil, MINIMUM_PUBLISHABLE_SAMPLE_SIZE].max, MAXIMUM_PUBLISHABLE_SAMPLE_SIZE].min
    end

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
      :original_publishable_event_page_count,
      :transition_exclusions,
      :event_inventory,
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
      check_options: nil,
      scope_at: Time.current,
      run_fetch: false,
      comparison_policy: :operator,
      fetch_cache_store: Distillator::FetchCacheStore,
      cache_compare: Distillator::CacheCompare
    )
      @website = website.is_a?(Website) ? website : Website.find(website)
      @cache = cache
      @evidence_by_kind = evidence_by_kind
      @check_options = Distillator::TransitionCheckOptions.coerce(check_options)
      @scope_at = scope_at
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
        original_publishable_event_page_count: original_publishable_event_page_count,
        transition_exclusions: excluded_records.map(&:snapshot),
        event_inventory: event_inventory,
        selected_candidate_tier_count: selected_candidate_tier_count,
        selection_rule: selection_rule,
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
      if event_scope?
        publishable_representative_webpages
      else
        size = @check_options.size_for(generic_representative_scope.count, default: FALLBACK_REPRESENTATIVE_SAMPLE_SIZE)
        generic_representative_scope.limit(size).to_a
      end
    end

    def candidate_webpage_count
      website.webpages.transition_candidates.count
    end

    def publishable_event_page_count
      @publishable_event_page_count ||= publishable_event_scope.count
    end

    def selected_candidate_tier_count
      event_scope? ? publishable_event_page_count : generic_representative_scope.count
    end

    def publishable_representative_webpages
      scope = publishable_event_scope
      order = @check_options.include_retired? ? :desc : :asc
      scope.order(archive_date: order, updated_at: :desc, id: :asc).limit(publishable_sample_size).to_a
    end

    def publishable_sample_size
      count = publishable_event_page_count
      return 0 if count.zero?

      @check_options.size_for(count, default: self.class.default_publishable_sample_size(count))
    end

    def publishable_event_scope
      scoped_publishable_events.without_reviewed_transition_exclusions
    end

    def event_inventory
      return unless event_scope?

      status = @check_options.include_retired? ? "historical_audit" : "active_event_scope"
      TransitionEventInventory::Result.new(status: status, archived_publishable_count: original_publishable_event_scope.archived(@scope_at).count)
    end

    def selection_rule
      rule = @check_options.selection_rule(event_site: event_scope?).dup
      rule << " Reviewed URL exclusions apply before sampling." if excluded_records.any?
      rule
    end

    def event_scope?
      return @event_scope if defined?(@event_scope)

      @event_scope = @check_options.include_retired? || EventSiteSelection.event_content_ids([website.id]).include?(website.id)
    end

    def scoped_publishable_events
      if @check_options.include_retired?
        original_publishable_event_scope.archived(@scope_at)
      else
        original_publishable_event_scope.active(@scope_at)
      end
    end

    def original_publishable_event_scope
      website.webpages.public_publishable_events
    end

    def original_publishable_event_page_count
      @original_publishable_event_page_count ||= original_publishable_event_scope.count
    end

    def excluded_records
      @excluded_records ||= begin
        scope = event_scope? ? scoped_publishable_events : website.webpages
        website.transition_exclusions.active.where(url: scope.select(:url)).order(:id).to_a
      end
    end

    def generic_representative_scope
      website.webpages.without_reviewed_transition_exclusions.reorder(updated_at: :desc, created_at: :desc, id: :asc)
    end

    def run_fetch?
      @run_fetch == true
    end

    def fetch_attempt_for(representative_webpage)
      if run_fetch? && representative_webpage.present?
        attempt = TransitionFetchSlot.call(uri: representative_webpage.url) { fetch_fresh_pair(representative_webpage) }
      end
      attempt || { attempted: false, result: nil, comparison: nil }
    end

    def fetch_fresh_pair(representative_webpage)
      # Both sides must fetch now; cached snapshots are inspection-only.
      render_js = Statements::RefreshWebpageStatementsService.sources_for_webpage(representative_webpage,
        default_language: website.default_language).any?(&:render_js?)
      fetch_result = fetch_cache_store.fetch(
        uri: representative_webpage.url,
        render_js: render_js,
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
          comparison_policy: comparison_policy,
          fresh_legacy: true,
          render_js: render_js
        )
      }
    end

    def normalize_comparison_policy(value)
      candidate = value.to_s.presence&.to_sym || :operator
      Distillator::CacheCompare::POLICIES.include?(candidate) ? candidate : :operator
    end
  end
end
