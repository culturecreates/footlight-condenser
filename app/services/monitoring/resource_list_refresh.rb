module Monitoring
  class ResourceListRefresh
    REFRESH_ISSUE = "resource_list_refresh".freeze
    IMPORT_ISSUE = "resource_list_import_incomplete".freeze
    IMPORT_GRACE = 6.hours

    def self.scheduled(page, at:)
      website = target_for(page)
      return unless website.monitorable?

      safely do
        state = ResourceListMonitoringState.create_or_find_by!(webpage_id: page.id) { |row| row.website = website }
        state.with_lock do
          if state.website_id != website.id
            state.update!(website: website, scheduled_at: at, verified_at: nil, completed_at: nil, contents_digest: nil,
              listed_urls: [], absent_archived_urls: [], pending_probe_urls: [], probed_at: nil, reappearances: 0, created_at: at)
          elsif state.scheduled_at.nil? || state.scheduled_at < at
            state.update!(scheduled_at: at)
          end
        end
      end
    end

    def self.refreshed(page, scheduled_at:, started_at:)
      with_current_attempt(page, scheduled_at) do |state, website|
        now = Time.current
        snapshot = Distillator::TransitionEventInventory.new(as_of: now).snapshot_for(page)
        if snapshot[:status] == "other_class"
          [REFRESH_ISSUE, IMPORT_ISSUE].each { |kind| ResourceListIssue.resolve(kind, website: website, page: page, at: now) }
          state.destroy!
          next
        end
        unless snapshot[:status] == "event" && Time.iso8601(snapshot.fetch(:refreshed_at)) >= started_at
          reason = snapshot[:reason].presence || "no fresh paired URL and RDF URI values were saved"
          record(REFRESH_ISSUE, state, at: scheduled_at, message: "Scheduled ResourceList refresh could not be verified (#{reason.humanize}).")
          next
        end

        verified_at = Time.iso8601(snapshot.fetch(:refresh_completed_at))
        if state.verified_at.nil? || state.verified_at < verified_at
          update_snapshot(state, snapshot, verified_at)
        end
        ResourceListIssue.resolve(REFRESH_ISSUE, website: website, page: page, at: verified_at)
        { scheduled_at: scheduled_at.iso8601(6), verified_at: verified_at.iso8601(6) }
      end
    end

    def self.imported(page, observation, contents_digest:)
      probe_args = with_current_attempt(page, Time.iso8601(observation.fetch(:scheduled_at))) do |state, website|
        next unless state.verified_at == Time.iso8601(observation.fetch(:verified_at))
        next if state.completed_at && state.completed_at >= state.verified_at

        now = Time.current
        if state.contents_digest != contents_digest
          record(IMPORT_ISSUE, state, at: now, message: "The import used a different ResourceList snapshot than the verified refresh.")
          next
        end
        imported_urls = website.webpages.event_pages.where(url: state.listed_urls).pluck(:url)
        missing = state.listed_urls - imported_urls
        if missing.present?
          record(IMPORT_ISSUE, state, at: now,
            message: "#{missing.size} event URLs from the verified ResourceList are missing from Condenser.",
            evidence: { missing_count: missing.size, example_urls: missing.first(5) })
          next
        end

        state.update!(completed_at: now)
        ResourceListIssue.resolve(IMPORT_ISSUE, website: website, page: page, at: now)
        [state.id, observation.fetch(:verified_at)] if state.pending_probe_urls.any?
      end
      enqueue_probe(probe_args) if probe_args
    end

    def self.failed(page, scheduled_at:, phase:, error:)
      with_current_attempt(page, scheduled_at) do |state, _website|
        if phase == :refresh
          next if state.verified_at && state.verified_at >= scheduled_at
        else
          next if state.completed_at && state.completed_at >= scheduled_at
        end
        kind = phase == :refresh ? REFRESH_ISSUE : IMPORT_ISSUE
        record(kind, state, at: scheduled_at, message: "Scheduled ResourceList #{phase} failed (#{error.class.name}).")
      end
    end

    def self.record(kind, state, at:, message:, evidence: {})
      ResourceListIssue.observe(kind, website: state.website, page: state.webpage, at: at, message: message,
        evidence: evidence.merge(scheduled_at: state.scheduled_at, last_verified_refresh_at: state.verified_at))
    end

    def self.target_for(page)
      page.discovery_target_website || page.website
    end

    def self.safely
      ResourceListMonitoringState.transaction(requires_new: true) { yield }
    rescue StandardError => error
      Rails.logger.error(event: "monitoring.resource_list_failed", error_class: error.class.name)
      nil
    end

    def self.with_current_attempt(page, scheduled_at)
      return unless page
      safely do
        state = ResourceListMonitoringState.find_by(webpage_id: page.id)
        next unless state

        state.with_lock do
          website = target_for(page)
          next unless website.monitorable? && state.website_id == website.id && state.scheduled_at == scheduled_at

          yield state, website
        end
      end
    end

    def self.update_snapshot(state, snapshot, verified_at)
      urls = snapshot.fetch(:urls).uniq
      removed = state.listed_urls - urls
      possible = state.absent_archived_urls | state.pending_probe_urls | removed
      archived = state.website.webpages.event_pages.archived(verified_at).where(url: possible).pluck(:url)
      reappeared = state.absent_archived_urls & archived & urls
      state.update!(verified_at: verified_at, contents_digest: snapshot.fetch(:contents_digest), listed_urls: urls,
        absent_archived_urls: (possible & archived) - urls,
        pending_probe_urls: (state.pending_probe_urls | reappeared) & archived & urls,
        reappearances: state.reappearances + reappeared.size)
      if reappeared.any?
        Rails.logger.info(event: "monitoring.event_url_reappeared", website_id: state.website_id,
          resource_list_id: state.webpage_id, count: reappeared.size, example_urls: reappeared.first(5))
      end
    end

    def self.enqueue_probe(args)
      ArchivedEventProbeJob.perform_later(*args)
    rescue StandardError => error
      Rails.logger.error(event: "monitoring.archived_event_enqueue_failed", error_class: error.class.name)
    end

    private_class_method :with_current_attempt, :update_snapshot, :enqueue_probe
  end
end
