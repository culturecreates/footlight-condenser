# frozen_string_literal: true

json.array! @websites do |website|
  pages = @webpage_summaries.fetch(website.id) { Distillator::WebsiteWebpageSummary.empty_summary }
  json.extract! website, :id, :name, :seedurl, :graph_name, :created_at, :updated_at
  json.statements_grouped @statements_grouped[website[:seedurl]]
  json.statements_refreshed_24hr @statements_refreshed_24hr[website[:seedurl]] ||= 0
  json.statements_updated_24hr @statements_updated_24hr[website[:seedurl]] ||= 0
  json.webpages pages[:total]
  json.event_pages pages[:by_class].fetch("Event")
  json.publishable_event_pages pages[:publishable]
  json.publishable_event_percentage pages[:publishable_event_page_percentage]
  json.publishable_event_page_percentage pages[:publishable_event_page_percentage]
  json.event_resources pages[:event_resources]
  json.publishable_event_resources pages[:publishable_event_resources]
  json.publishable_event_resource_percentage pages[:publishable_event_resource_percentage]
  json.event_languages pages[:event_languages]
  json.fully_localized_event_resources pages[:fully_localized_event_resources]
  json.flags @flags[website[:seedurl]]
  json.updates @updated[website[:seedurl]]
  if @inventory_freshness
    json.inventory_freshness @inventory_freshness.fetch(website.id)
    json.data_as_of @inventory_data_as_of.iso8601
  end
end
