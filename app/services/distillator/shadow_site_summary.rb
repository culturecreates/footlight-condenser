require "cgi"

module Distillator
  class ShadowSiteSummary
    Result = Struct.new(
      :website,
      :cache,
      :cohort_key,
      :cohort_label,
      :status,
      :fetch_status,
      :statements_status,
      :export_status,
      :production_backend,
      :testing_backend,
      :health_summary,
      :health_status,
      :health_severity,
      :latest_refresh,
      :latest_successful_refresh,
      :issue_key,
      :blockers,
      :warnings,
      :cache_link_payload,
      :last_checked,
      :promotable,
      :priority,
      :mode_label,
      :production_backend_label,
      :readiness_label,
      :severity,
      :primary_blocker,
      :primary_action,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(website:, cache: nil, stale_after: Distillator::CacheHealth::STALE_AFTER, evidence_by_kind: nil, include_cache_links: false)
      @website = website
      @cache = cache
      @stale_after = stale_after
      @evidence_by_kind = evidence_by_kind
      @include_cache_links = include_cache_links
    end

    def call
      Result.new(
        website: website,
        cache: cache,
        cohort_key: cohort_key,
        cohort_label: cohort_label,
        status: transition_status.status,
        fetch_status: transition_status.fetch,
        statements_status: transition_status.statements,
        export_status: transition_status.export,
        production_backend: production_backend,
        testing_backend: :condenser,
        health_summary: health_summary,
        health_status: health_status,
        health_severity: health_severity,
        latest_refresh: cache&.scrape_date,
        latest_successful_refresh: cache&.successful_refresh,
        issue_key: cache&.primary_issue_key,
        blockers: transition_status.blockers,
        warnings: transition_status.warnings,
        cache_link_payload: include_cache_links? ? cache_link_payload : nil,
        last_checked: transition_status.last_checked,
        promotable: transition_status.status == :ready,
        priority: website.lavitrine_pipeline?,
        mode_label: Distillator::RolloutCopy.label(website.distillator_mode),
        production_backend_label: Distillator::RolloutCopy.active_backend_label(website.distillator_mode),
        readiness_label: transition_status.readiness_label,
        severity: transition_status.severity,
        primary_blocker: transition_status.primary_blocker,
        primary_action: operator_next_action
      )
    end

    private

    attr_reader :website, :cache, :stale_after, :evidence_by_kind

    def health_summary
      return "Unknown" unless evidence_exists?

      label = cache.primary_issue_label.presence || cache.health_status.to_s.humanize
      "#{cache.health_severity.to_s.humanize}: #{label}"
    end

    def health_status
      return "unknown" unless evidence_exists?

      cache.health_status.to_s.presence || "unknown"
    end

    def health_severity
      return "unknown" unless evidence_exists?

      cache.health_severity.to_s.presence || "unknown"
    end

    def cohort_key
      website.respond_to?(:distillator_primary_cohort_key) ? website.distillator_primary_cohort_key : nil
    end

    def cohort_label
      website.respond_to?(:distillator_primary_cohort_label) ? website.distillator_primary_cohort_label : nil
    end

    def evidence_exists?
      cache.present?
    end

    def transition_status
      @transition_status ||= Distillator::TransitionStatus.call(
        website: website,
        cache: cache,
        evidence_by_kind: resolved_evidence_by_kind
      )
    end

    def cache_link_payload
      @cache_link_payload ||= Distillator::TransitionCheck.call(
        website: website,
        cache: cache,
        evidence_by_kind: resolved_evidence_by_kind
      ).cache_link_payload
    end

    def operator_next_action
      Distillator::OperatorNextAction.call(
        website: website,
        transition_status: transition_status,
        cache_link_payload: include_cache_links? ? cache_link_payload : nil
      )
    end

    def production_backend
      @production_backend ||= Distillator::FetchMode.rollout_resolution_object(website: website).active_backend
    end

    def include_cache_links?
      @include_cache_links == true
    end

    def resolved_evidence_by_kind
      evidence_by_kind || (website.respond_to?(:latest_transition_evidences_by_kind) ? website.latest_transition_evidences_by_kind : {})
    end
  end
end
