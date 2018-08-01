alternatives = []
json.statements do
  @statements.each do |statement|
    if statement.source.selected
      json.set! build_key(statement) do
        json.(statement, :cache, :status, :status_origin, :cache_refreshed, :cache_changed)
        json.label statement.source.property.label
        json.language statement.source.language
      end
    else
      alternatives << statement
    end
  end
end
json.alternatives alternatives.each do |statement|
  json.set! build_key(statement) do
    json.(statement, :cache, :status, :status_origin, :cache_refreshed, :cache_changed)
    json.label statement.source.property.label
    json.language statement.source.language
  end
end
