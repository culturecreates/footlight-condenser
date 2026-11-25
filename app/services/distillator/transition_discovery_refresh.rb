module Distillator
  class TransitionDiscoveryRefresh
    Result = Struct.new(:added_page_ids, :prior_archive_dates, :proof, keyword_init: true)

    def self.call(website:, cancellation_check: nil)
      before = inventory(website)
      event_lists = before.lists.reject { |list| list[:status] == "other_class" }
      return Result.new(added_page_ids: [], prior_archive_dates: {}) if event_lists.empty?

      started_at = Time.current.floor(6)
      definition = TransitionEventInventory.definition_digest(website.id)
      TransitionEventInventory.list_pages(website.id).where(id: event_lists.pluck(:webpage_id)).order(:id).each do |page|
        cancellation_check&.call
        refresh(page)
      end

      verified_lists = inventory(website).lists.reject { |list| list[:status] == "other_class" }
      unless event_lists.pluck(:webpage_id) == verified_lists.pluck(:webpage_id) &&
          definition == TransitionEventInventory.definition_digest(website.id)
        raise TransitionRun::DiscoveryEvidenceError.new("ResourceList configuration changed during discovery.",
          reason: :discovery_configuration_changed, next_action: :run_thorough)
      end
      urls = verified_lists.to_h { |list| [list.fetch(:webpage_id), list.fetch(:url)] }
      activity = WebpageOperationEvidence.for_urls(urls, discovery_only: true)
      diagnostics = ResourceListReadiness.for_lists(verified_lists, activity: activity).index_by { |list| list[:webpage_id] }
      verified_lists.each do |list|
        unless list[:status] == "event" && Time.iso8601(list.fetch(:refreshed_at)) >= started_at
          id = list.fetch(:webpage_id)
          diagnosis = diagnostics.fetch(id)
          reason = diagnosis[:reason] unless diagnosis[:reason] == :discovery_complete
          reason ||= :missing_statement_extraction
          guidance = ResourceListReadiness.guidance(reason)
          raise TransitionRun::DiscoveryEvidenceError.new(
            "ResourceList ##{id} statement extraction could not be verified. #{guidance.fetch(:message)}",
            webpage_id: id, reason: reason, next_action: guidance[:next_action])

        end
      end

      added_page_ids = verified_lists.flat_map do |list|
        cancellation_check&.call
        AddWebpagesJob.perform_now(list.fetch(:webpage_id), selected_only: true, refresh_new: false,
          expected_discovery: { website_id: website.id, contents_digest: list.fetch(:contents_digest) })
      end
      to_initialize = website.webpages.where(id: added_page_ids | incomplete_listed_pages(website, verified_lists))
        .reorder(:id)
      # Statement refresh can update archive dates on every language of an event.
      prior_archive_dates = website.webpages.where(rdf_uri: to_initialize.reorder(nil).select(:rdf_uri)).pluck(:id, :archive_date).to_h
      to_initialize.each do |page|
        cancellation_check&.call
        refresh(page)
      end

      finished_at = Time.current
      finished = inventory(website, as_of: finished_at)
      finished_lists = finished.lists.select { |list| list[:status] == "event" }
      unless finished.status == "confirmed_discovery" && list_versions(finished_lists) == list_versions(verified_lists)
        raise TransitionRun::DiscoveryEvidenceError.new("URL reconciliation could not be verified. Review the lists and retry.",
          reason: :pending_reconciliation, next_action: :reconcile_urls)
      end
      if finished.unpublishable_urls_count.to_i.positive?
        listed = finished.unpublishable_listed_pages.group_by { |page| page[:rdf_uri] }
        scope = active_public_event_pages(website, as_of: finished_at).where(rdf_uri: listed.keys)
        requirements = Events::ResourcePublishability.new(scope).missing_requirements
        blockers = listed.map do |uri, pages|
          { rdf_uri: uri, webpages: pages, fields: requirements.fetch(uri, []) }
        end
        raise TransitionRun::UnpublishableEvents.new(blockers)
      end

      warnings = finished_lists.filter_map { |list| list.slice(:webpage_id, :warning) if list[:warning] }
      proof = {
        definition: definition, lists: list_versions(finished_lists),
        refresh_completed_at: finished_lists.pluck(:refresh_completed_at).max,
        stages: {
          source_fetch: verified_lists.map do |list|
            observed = activity.fetch(list[:webpage_id]).dig(:extraction, :saved_inputs).filter_map do |input|
              primary = input["primary"]
              primary if primary && Time.iso8601(input.fetch("recorded_at")) >= started_at
            end
            { webpage_id: list[:webpage_id], responses: observed.uniq }
          end,
          statement_extraction: verified_lists.map { |list| list.slice(:webpage_id, :refreshed_at, :refresh_completed_at) },
          reconciliation: { lists_checked: verified_lists.size, webpages_created: added_page_ids.size }
        }
      }
      proof[:warnings] = warnings if warnings.any?
      Result.new(added_page_ids: added_page_ids, prior_archive_dates: prior_archive_dates, proof: proof)
    rescue AddWebpagesJob::InvalidResourceListError => error
      raise TransitionRun::ConfigurationChanged, "#{error.message}. Review the ResourceLists and retry."
    end

    def self.verify(website, proof, as_of:)
      current = inventory(website, as_of: as_of)
      lists = current.lists.select { |list| list[:status] == "event" }
      current.status == "confirmed_discovery" && current.unpublishable_urls_count.to_i.zero? &&
        proof["definition"] == TransitionEventInventory.definition_digest(website.id) &&
        proof["lists"] == list_versions(lists)
    end

    def self.list_versions(lists)
      lists.to_h { |list| [list.fetch(:webpage_id).to_s, list.fetch(:contents_digest)] }
    end

    def self.incomplete_listed_pages(website, lists)
      urls = TransitionEventInventory.discovery_scope(lists.pluck(:webpage_id))
        .where(properties: { label: AddWebpagesJob::WEBPAGE_URL_LIST_LABEL })
        .where(selected_individual: true, sources: { selected: true }).pluck(:cache).flat_map { |cache| JSON.parse(cache) }
      active_pages = active_public_event_pages(website)
      publishable = active_pages.pages_of_publishable_events
      eligible = active_pages.without_reviewed_transition_exclusions
      incomplete = eligible.where(url: urls).where.not(id: publishable.select(:id))
      eligible.where(rdf_uri: incomplete.select(:rdf_uri)).ids
    end

    def self.inventory(website, as_of: Time.current)
      candidates = active_public_event_pages(website, as_of: as_of).pages_of_publishable_events.without_reviewed_transition_exclusions
      TransitionEventInventory.new(as_of: as_of).for_websites([website.id], events: candidates).fetch(website.id)
    end

    def self.active_public_event_pages(website, as_of: Time.current)
      website.webpages.event_pages.public_source_urls.active(as_of)
    end

    def self.refresh(page)
      RefreshRunner.call(webpage: page, refresh_helper: ApplicationController.helpers, scrape_options: { force_scrape: true, force_scrape_every_hrs: 0 })
    end

    private_class_method :list_versions, :incomplete_listed_pages, :inventory, :active_public_event_pages, :refresh
  end
end
