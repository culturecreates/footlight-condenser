json.set! build_key(statement) do
  json.value statement.cache
  json.(statement, :status, :status_origin, :cache_refreshed, :cache_changed)
  json.label statement.source.property.label
  statement.cache
  json.language statement.source.language
  json.datatype statement.source.property.value_datatype
end
