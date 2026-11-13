module Distillator
  class WebsiteOperationStatus
    attr_reader :website, :cache, :comparison

    def initialize(website:, cache: nil)
      @website = website
      @cache = cache
      # This section describes the completed comparison, not a later cache fetch.
      run = website.latest_completed_transition_run
      @comparison = Distillator::TransitionStatus.call(website: website, cache: nil,
        evidence_by_kind: website.latest_transition_evidences_by_kind, now: run&.completed_at || Time.current)
    end

    def activation
      return @activation if defined?(@activation)

      latest = website.rollout_events.order(created_at: :desc, id: :desc).first
      @activation = website.distillator_mode == "active" && latest&.to_mode == "active" ? latest : nil
    end

    def self.reviewed?(event)
      snapshot = event.readiness_snapshot.to_h
      snapshot["review_activation"] == true || snapshot["event"] == "rollout.review_activate"
    end

    def self.event_label(event)
      return "Activated after review" if event.to_mode == "active" && reviewed?(event)
      return "Activated with override" if event.to_mode == "active" && event.readiness_snapshot["override"] == true
      return "Activated" if event.to_mode == "active"

      "#{event.from_mode.presence || 'unknown'} to #{event.to_mode}"
    end

    def accepted_comparison?
      return false unless activation && self.class.reviewed?(activation)

      run = website.latest_completed_transition_run
      snapshot = activation.readiness_snapshot.to_h
      run && snapshot["transition_run_id"].to_s == run.id.to_s &&
        snapshot["configuration_digest"] == run.configuration_digest &&
        website.transition_run_blocker.blank? && comparison.blockers.empty? &&
        [comparison.fetch, comparison.statements, comparison.export].all? { |state| state == :passed } &&
        (comparison.warnings - Array(snapshot["warnings"])).empty?
    end

    def observed_fetch
      return { label: "Awaiting active refresh" } unless cache&.scrape_date

      if activation && cache.scrape_date <= activation.created_at
        return { label: "Awaiting active refresh", previous_attempt_at: cache.scrape_date }
      end
      signals = cache.signals.to_h.stringify_keys
      backend = signals["fetch_backend"].presence
      failed = Distillator::TransitionStatus.call(website: website, cache: cache, evidence_by_kind: {}).fetch == :failed
      label = if failed
        "Latest observed fetch failed"
      elsif %w[legacy replay].include?(backend)
        "Latest fetch did not use the active Condenser backend"
      else
        "Latest observed fetch: #{cache.health_status.to_s.humanize.presence || 'recorded'}"
      end
      { label: label, attempted_at: cache.scrape_date, url: cache.normalized_url,
        final_url: cache.final_url.presence, backend: backend, failed: failed,
        redirected: cache.redirected == true || (cache.final_url.present? && cache.final_url != cache.normalized_url) }
    end

    def statement_counts
      @statement_counts ||= Statement.selected_for_transition.joins(:source)
        .where(sources: { website_id: website.id },
          webpage_id: website.webpages.active.event_pages.select(:id)).group(:status).count
    end
  end
end
