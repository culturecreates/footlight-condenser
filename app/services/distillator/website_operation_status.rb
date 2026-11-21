module Distillator
  class WebsiteOperationStatus
    attr_reader :website, :cache, :comparison, :completed_run, :latest_run, :evidence_by_kind

    def initialize(website:, cache: nil, transition_run: nil)
      @website = website
      @cache = cache
      # Bind IDs, evidence and status to one observation. A run finishing while
      # the page renders cannot replace only part of the displayed comparison.
      @latest_run = transition_run || website.latest_transition_run
      @completed_run = if latest_run&.status == "completed"
        latest_run
      elsif latest_run
        website.transition_runs.completed.where("id < ?", latest_run.id).order(completed_at: :desc, id: :desc).first
      end
      @evidence_by_kind = completed_run ? completed_run.transition_evidences.index_by(&:check_kind) : {}
      @comparison = Distillator::TransitionStatus.call(website: website, cache: nil,
        evidence_by_kind: evidence_by_kind, current_run: latest_run, now: completed_run&.completed_at || Time.current)
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
      return "Rolled back to Legacy Wringer" if event.from_mode == "active" && event.to_mode == "legacy"
      return "Returned to Shadow (Wringer)" if event.from_mode == "active" && event.to_mode == "shadow"
      return "Activated after review" if event.to_mode == "active" && reviewed?(event)
      return "Activated with override" if event.to_mode == "active" && event.readiness_snapshot["override"] == true
      return "Activated" if event.to_mode == "active"

      "#{event.from_mode.presence || 'unknown'} to #{event.to_mode}"
    end

    def accepted_comparison?
      reviewed_completed_comparison? && website.transition_run_blocker(latest_run).blank?
    end

    def completed_comparison
      @completed_comparison ||= Distillator::TransitionStatus.for_completed_run(website: website, run: completed_run) if completed_run
    end

    def reviewed_completed_comparison?
      return false unless activation && self.class.reviewed?(activation)

      run = completed_run
      snapshot = activation.readiness_snapshot.to_h
      run && snapshot["transition_run_id"].to_s == run.id.to_s &&
        snapshot["configuration_digest"] == run.configuration_digest &&
        completed_comparison.blockers.empty? &&
        [completed_comparison.fetch, completed_comparison.statements, completed_comparison.export].all? { |state| state == :passed } &&
        (completed_comparison.warnings - Array(snapshot["warnings"])).empty?
    end

    def observed_fetch
      return { label: "Awaiting active refresh" } unless cache&.scrape_date

      if activation && cache.scrape_date <= activation.created_at
        return { label: "Awaiting active refresh", previous_attempt_at: cache.scrape_date }
      end
      signals = cache.signals.to_h.stringify_keys
      backend = signals["fetch_backend"].presence
      failed = Distillator::TransitionStatus.cache_fetch_failed?(cache)
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
