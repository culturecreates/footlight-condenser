module Distillator
  class TransitionDiscoveryRefresh
    Result = Struct.new(:added_page_ids, :prior_archive_dates, keyword_init: true)

    def self.call(website:, cancellation_check: nil)
      before = inventory(website)
      event_lists = before.lists.reject { |list| list[:status] == "other_class" }
      return Result.new(added_page_ids: [], prior_archive_dates: {}) if event_lists.empty?

      started_at = Time.current.floor(6)
      website.webpages.where(id: event_lists.pluck(:webpage_id)).order(:id).each do |page|
        cancellation_check&.call
        refresh(page)
      end

      verified_lists = inventory(website).lists.reject { |list| list[:status] == "other_class" }
      verified_lists.each do |list|
        unless list[:status] == "event" && Time.iso8601(list.fetch(:refreshed_at)) >= started_at
          reason = list[:reason].presence || "no fresh statement values were saved"
          raise TransitionRun::ConfigurationChanged, "ResourceList ##{list.fetch(:webpage_id)} refresh was unverified (#{reason.humanize}). Review the list and retry."
        end
      end

      added_page_ids = verified_lists.flat_map do |list|
        cancellation_check&.call
        AddWebpagesJob.perform_now(list.fetch(:webpage_id), selected_only: true, refresh_new: false)
      end
      to_initialize = website.webpages.where(id: added_page_ids | uninitialized_listed_pages(website, verified_lists))
        .reorder(:id)
      # Statement refresh can update archive dates on every language of an event.
      prior_archive_dates = website.webpages.where(rdf_uri: to_initialize.reorder(nil).select(:rdf_uri)).pluck(:id, :archive_date).to_h
      to_initialize.each do |page|
        cancellation_check&.call
        refresh(page)
      end

      if verified_lists.any? && inventory(website).status != "confirmed_discovery"
        raise TransitionRun::ConfigurationChanged, "ResourceList import could not be verified. Review the lists and retry."
      end

      Result.new(added_page_ids: added_page_ids, prior_archive_dates: prior_archive_dates)
    end

    def self.uninitialized_listed_pages(website, lists)
      urls = TransitionEventInventory.discovery_scope([website.id])
        .where(webpage_id: lists.pluck(:webpage_id), properties: { label: AddWebpagesJob::WEBPAGE_URL_LIST_LABEL })
        .where(selected_individual: true, sources: { selected: true }).pluck(:cache).flat_map { |cache| JSON.parse(cache) }
      website.webpages.event_pages.where(url: urls).where.missing(:statements).ids
    end

    def self.inventory(website)
      now = Time.current
      candidates = website.webpages.public_publishable_events.active(now).without_reviewed_transition_exclusions
      TransitionEventInventory.new(as_of: now).for_websites([website.id], events: candidates).fetch(website.id)
    end

    def self.refresh(page)
      RefreshRunner.call(webpage: page, refresh_helper: ApplicationController.helpers, scrape_options: { force_scrape_every_hrs: 0 })
    end

    private_class_method :uninitialized_listed_pages, :inventory, :refresh
  end
end
