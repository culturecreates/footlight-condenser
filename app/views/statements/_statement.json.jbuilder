json.extract! statement, :id, :cache, :status, :status_origin, :cache_refreshed, :cache_changed, :created_at, :updated_at
json.property_label statement.property.label
json.property_language statement.property.language
json.url statement_url(statement, format: :json)
