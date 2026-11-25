module Distillator
  class TransitionTimeEstimate
    def self.for_site(website)
      for_sites([website])[website.id]
    end

    def self.for_sites(websites, check_options: nil, shadow_first: false)
      ids = websites.map(&:id)
      ranked = TransitionRun.current_checks.completed.where(website_id: ids).where.not(started_at: nil).where.not(completed_at: nil)
        .select("distillator_transition_runs.*, ROW_NUMBER() OVER (PARTITION BY website_id ORDER BY id DESC) AS timing_rank")
      runs = TransitionRun.from("(#{ranked.to_sql}) distillator_transition_runs").where("timing_rank <= 6")
        .includes(:transition_evidences).group_by(&:website_id)
      pages = Webpage.event_pages.public_source_urls.active.where(website_id: ids)
      candidates = check_options&.event_resource_scope? ? pages.pages_of_publishable_events : pages.publishable
      counts = candidates.without_reviewed_transition_exclusions.group(:website_id).count
      websites.to_h do |website|
        estimate = nil
        durations = Array(runs[website.id]).filter_map do |run|
          count = run.transition_evidences.find { |evidence| evidence.check_kind == "fetch_parity" }&.details.to_h["representative_webpage_count"].to_i
          duration = run.completed_at - run.started_at
          duration / count if count.positive? && duration > 0.1
        end.sort
        count = counts[website.id].to_i
        count = check_options.size_for(count, default: TransitionCheck.default_publishable_sample_size(count)) if check_options
        checks = !shadow_first && website.distillator_mode == "active" ? 1 : 2
        estimate = (durations[durations.length / 2] * count * checks).ceil if durations.any? && count.positive?
        [website.id, estimate]
      end
    end

    def self.remaining(items, now: Time.current)
      unfinished = items.select { |item| item.status.in?(%w[queued running]) }
      unknown = unfinished.count { |item| item.estimated_seconds.nil? }
      late = false
      seconds = unfinished.sum do |item|
        next 0 unless item.estimated_seconds
        estimate = item.estimated_seconds.to_f
        if item.status == "running"
          estimate /= 2 if item.phase == "postcheck" && (item.pre_run_id || item.initial_mode != "active")
          estimate -= now - item.phase_started_at if item.phase_started_at
          late ||= estimate <= 0
        end
        [estimate, 0].max
      end
      { seconds: seconds.ceil, unknown: unknown, overdue: late }
    end
  end
end
