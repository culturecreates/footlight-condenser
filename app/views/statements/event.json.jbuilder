@statements.each do |statement|
  json.set! build_key(statement) do
    json.(statement, :cache, :status, :status_origin, :cache_refreshed, :cache_changed)
    json.label statement.property.label
    json.language statement.property.language
  end
end
