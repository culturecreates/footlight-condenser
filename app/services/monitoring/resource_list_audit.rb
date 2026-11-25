module Monitoring
  class ResourceListAudit
    def self.call(now: Time.current)
      ResourceListRefresh.safely do
        websites = Website.where(monitorable: true).select(&:refresh_scheduled?).index_by(&:id)
        lists = Distillator::TransitionEventInventory.list_pages(websites.keys).includes(:website, :discovery_target_website)
        states = ResourceListMonitoringState.where(webpage_id: lists.select(:id)).index_by(&:webpage_id)
        lists.each do |page|
          website = websites.fetch(ResourceListRefresh.target_for(page).id)
          state = states[page.id]
          if state.nil?
            snapshot = Distillator::TransitionEventInventory.new(as_of: now).snapshot_for(page)
            next if snapshot[:status] == "other_class"

            state = ResourceListMonitoringState.create_or_find_by!(webpage_id: page.id) do |entry|
              entry.assign_attributes(website: website, created_at: now)
            end
          end

          state.with_lock do
            next unless state.website_id == website.id

            check_completion(state, now)
            check_publishability(state, now) if state.verified_at
          end
        end
        resolve_corrected_events(now)
      end
    end

    def self.check_completion(state, now)
      grace = ResourceListRefresh::IMPORT_GRACE
      anchor = state.completed_at || state.created_at
      deadline = anchor + state.website.schedule_every_days.days + grace
      if state.scheduled_at && (state.completed_at.nil? || state.completed_at < state.scheduled_at)
        deadline = [deadline, state.scheduled_at + grace].min
      end
      refresh_verified = state.scheduled_at && state.verified_at && state.verified_at >= state.scheduled_at
      import_pending = refresh_verified && (state.completed_at.nil? || state.completed_at < state.verified_at)
      deadline = state.scheduled_at + grace if import_pending
      return if now < deadline

      kind = import_pending ? ResourceListRefresh::IMPORT_ISSUE : ResourceListRefresh::REFRESH_ISSUE
      return if MonitoringIssue.open_issues.exists?(kind: kind, webpage_id: state.webpage_id, seedurl: state.website.seedurl)

      phase = import_pending ? "import" : "refresh"
      message = "Scheduled ResourceList #{phase} is overdue."
      ResourceListRefresh.record(kind, state, at: now, message: message, evidence: { deadline: deadline, last_completed_at: state.completed_at })
    end

    def self.check_publishability(state, now)
      kind = "listed_event_unpublishable"
      pages = state.website.webpages.event_pages.public_source_urls.active(now)
        .where(url: state.listed_urls).where(created_at: ..(now - ResourceListRefresh::IMPORT_GRACE)).not_publishable
      count = pages.count
      if count.zero?
        ResourceListIssue.resolve(kind, website: state.website, page: state.webpage, at: now)
        return
      end

      ResourceListRefresh.record(kind, state, at: now,
        message: "#{count} listed events in the current archive window lack publishable statements.",
        evidence: { affected_count: count, example_urls: pages.order(:id).limit(5).pluck(:url) })
    end

    def self.resolve_corrected_events(now)
      cases = MonitoringIssue.open_issues.where(kind: "possible_missed_event").find_each
      cases.each do |issue|
        page = Webpage.includes(:website).find_by(id: issue.webpage_id)
        next unless page&.website&.monitorable? && page.archive_date
        next unless issue.evidence["observed_date"]

        observed = Time.zone.iso8601(issue.evidence.fetch("observed_date"))
        next unless page.archive_date >= observed - 24.hours

        confirmed = page.statements.joins(source: :property)
          .where(sources: { website_id: page.website_id, selected: true }, properties: { label: "Dates" })
          .where(status: Webpage::PUBLISHABLE_STATUSES).where("cache_refreshed > ?", issue.last_seen_at).exists?
        ResourceListIssue.resolve(issue.kind, website: page.website, page: page, at: now) if confirmed
      end
    end
    private_class_method :check_completion, :check_publishability, :resolve_corrected_events
  end
end
