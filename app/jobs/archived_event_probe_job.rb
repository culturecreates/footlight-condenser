class ArchivedEventProbeJob < ApplicationJob
  queue_as :default

  PROBES_PER_LIST_REFRESH = 5

  def perform(state_id, snapshot_stamp)
    state = ResourceListMonitoringState.find_by(id: state_id)
    return unless state

    verified_at = Time.iso8601(snapshot_stamp)
    urls = state.with_lock do
      next [] unless state.website.monitorable? && state.verified_at == verified_at && state.probed_at != verified_at

      picked = state.pending_probe_urls.first(PROBES_PER_LIST_REFRESH)
      state.update!(pending_probe_urls: state.pending_probe_urls - picked, probed_at: verified_at)
      picked
    end

    state.website.webpages.event_pages.public_source_urls.archived.where(url: urls).find_each do |page|
      result = Monitoring::ArchivedEventDates.call(page)
      Rails.logger.info(event: "monitoring.archived_event_probe", website_id: state.website_id, webpage_id: page.id,
        result: result.reason || "future_date_found")
      next unless result.date

      Monitoring::ResourceListRefresh.safely do
        page.reload
        now = Time.current
        next unless page.archive_date && page.archive_date <= now && page.archive_date < result.date - 24.hours
        next unless ResourceListMonitoringState.exists?(id: state.id, website_id: page.website_id, verified_at: verified_at)

        Monitoring::ResourceListIssue.observe("possible_missed_event", website: state.website, page: page, at: now,
          source_id: result.source_id, evidence: { resource_list_id: state.webpage_id, last_verified_refresh_at: verified_at,
            archive_date: page.archive_date, observed_date: result.date },
          message: "An archived event URL advertises a future date. Recorded archive date #{page.archive_date.to_date}. " \
            "Observed date #{result.date.to_date}. Review the event and refresh if appropriate.")
      end
    end
  end
end
