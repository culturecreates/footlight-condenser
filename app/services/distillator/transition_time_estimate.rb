module Distillator
  class TransitionTimeEstimate
    def self.for_site(website)
      for_sites([website])[website.id]
    end

    def self.for_sites(websites)
      ids = websites.map(&:id)
      ranked = TransitionRun.completed.where(website_id: ids).where.not(started_at: nil).where.not(completed_at: nil)
        .select("distillator_transition_runs.*, ROW_NUMBER() OVER (PARTITION BY website_id ORDER BY id DESC) AS timing_rank")
      runs = TransitionRun.from("(#{ranked.to_sql}) distillator_transition_runs").where("timing_rank <= 6")
        .includes(:transition_evidences).group_by(&:website_id)
      counts = Webpage.publishable.where(website_id: ids).where(<<~SQL.squish).group(:website_id).count
        NOT EXISTS (SELECT 1 FROM distillator_transition_exclusions e
          WHERE e.website_id = webpages.website_id AND e.url = webpages.url AND e.revoked_at IS NULL)
      SQL
      websites.to_h do |website|
        estimate = nil
        durations = Array(runs[website.id]).filter_map do |run|
          count = run.transition_evidences.find { |evidence| evidence.check_kind == "fetch_parity" }&.details.to_h["representative_webpage_count"].to_i
          duration = run.completed_at - run.started_at
          duration / count if count.positive? && duration > 0.1
        end.sort
        count = counts[website.id].to_i
        estimate = (durations[durations.length / 2] * count * (website.distillator_mode == "active" ? 1 : 2)).ceil if durations.any? && count.positive?
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
          estimate /= 2 if item.phase == "postcheck" && item.initial_mode != "active"
          estimate -= now - item.phase_started_at if item.phase_started_at
          late ||= estimate <= 0
        end
        [estimate, 0].max
      end
      { seconds: seconds.ceil, unknown: unknown, overdue: late }
    end
  end
end
