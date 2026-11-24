module Distillator
  class WebsiteInventoryFreshness
    STATUS_LABELS = {
      "confirmed_discovery" => "Verified",
      "stale" => "Stale",
      "discovery_unverified" => "Unverified",
      "discovery_pending_import" => "Awaiting import",
      "no_discovery_lists" => "No event lists",
      "no_event_discovery" => "No event lists"
    }.freeze

    def self.for_websites(website_ids, as_of: Time.current)
      return {} if website_ids.empty?

      events = Webpage.event_pages.where(website_id: website_ids)
      latest_added = events.where(created_at: ..as_of).group(:website_id).maximum(:created_at)
      reviewed = TransitionExclusion.active.where("distillator_transition_exclusions.website_id = webpages.website_id")
        .where("distillator_transition_exclusions.url = webpages.url")
      candidates = events.publishable.where.not(reviewed.arel.exists)
      inventories = TransitionEventInventory.new(as_of: as_of).for_websites(website_ids, events: candidates)

      inventories.to_h do |website_id, inventory|
        last_added = latest_added[website_id]
        recent_refresh = inventory.lists.filter_map { |list| Time.iso8601(list[:refreshed_at]) if list[:refreshed_at] }.max
        unverified = inventory.lists.select { |list| list[:status] == "unverified" }
        status = inventory.status
        status = "stale" if status == "discovery_unverified" && unverified.all? { |list| list[:reason] == "stale_list" }

        [website_id, {
          status: status,
          label: STATUS_LABELS.fetch(status),
          latest_list_refresh_at: recent_refresh&.utc&.iso8601,
          new_event_age_days: last_added && (as_of.to_date - last_added.to_date).to_i,
          selected_event_urls_missing: inventory.selected_event_urls_missing
        }]
      end
    end
  end
end
