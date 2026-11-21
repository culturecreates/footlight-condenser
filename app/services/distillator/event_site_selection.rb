module Distillator
  class EventSiteSelection
    def self.eligible_ids(websites)
      sites = Array(websites).select { |site| WebsiteIndexGroups.category(site).in?(%i[scheduled unscheduled]) && Website::DISTILLATOR_MODES.include?(site.distillator_mode) }
      ids = sites.map(&:id)
      page_ids = Webpage.event_pages.where(website_id: ids).distinct.pluck(:website_id)
      source_ids = Source.joins(property: :rdfs_class).where(website_id: ids, selected: true, rdfs_classes: { name: "Event" })
        .distinct.pluck(:website_id)
      (page_ids | source_ids) & ids
    end
  end
end
