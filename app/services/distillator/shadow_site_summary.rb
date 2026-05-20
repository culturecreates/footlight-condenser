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
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(website:, cache: nil, stale_after: Distillator::CacheHealth::STALE_AFTER)
      @website = website
      @cache = cache
      @stale_after = stale_after
    end

    def call
      Result.new(
        website: website,
        cache: cache,
        cohort_key: cohort_key,
        cohort_label: cohort_label,
        status: transition_check.status,
        fetch_status: transition_check.fetch,
        statements_status: transition_check.statements,
        export_status: transition_check.export,
        production_backend: transition_check.active_backend,
        testing_backend: :condenser,
        health_summary: health_summary,
        health_status: health_status,
        health_severity: health_severity,
        latest_refresh: cache&.scrape_date,
        latest_successful_refresh: cache&.successful_refresh,
        issue_key: cache&.primary_issue_key,
        blockers: transition_check.blocking_issues,
        warnings: transition_check.warnings,
        cache_link_payload: transition_check.cache_link_payload,
        last_checked: transition_status.last_checked,
        promotable: transition_check.promotable,
        priority: transition_check.priority
      )
    end

    private

    attr_reader :website, :cache, :stale_after

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
        evidence_by_kind: website.respond_to?(:latest_transition_evidences_by_kind) ? website.latest_transition_evidences_by_kind : {}
      )
    end

    def transition_check
      @transition_check ||= Distillator::TransitionCheck.call(
        website: website,
        cache: cache,
        evidence_by_kind: website.respond_to?(:latest_transition_evidences_by_kind) ? website.latest_transition_evidences_by_kind : {}
      )
    end
  end
end
