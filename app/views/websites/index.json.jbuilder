# frozen_string_literal: true

json.array! @websites do |website|
  json.extract! website, :id, :name, :seedurl, :graph_name, :created_at, :updated_at
  json.statements_grouped @statements_grouped[website[:seedurl]]
  json.statements_refreshed_24hr @statements_refreshed_24hr[website[:seedurl]] ||= 0
  json.statements_updated_24hr @statements_updated_24hr[website[:seedurl]] ||= 0
  json.webpages @webpages[website]
  json.flags @flags[website[:seedurl]]
  json.updates @updated[website[:seedurl]]
end
