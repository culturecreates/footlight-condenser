json.extract! statement, :id, :cache, :status, :status_origin, :cache_refreshed, :cache_changed, :created_at, :updated_at
json.label statement.source.property.label
json.language statement.source.language
json.value_datatype statement.source.property.value_datatype
json.event_name_en "Hardcoded event name in English"
json.url statement_url(statement, format: :json)
