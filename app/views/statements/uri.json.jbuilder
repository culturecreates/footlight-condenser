alternatives = []
json.subject_uri params[:rdf_uri]
json.subject_class @statements.first.source.property.rdfs_class.name
json.statements do
  @statements.each do |statement|
    if statement.source.selected
      json.partial! "statements/uri", statement: statement
    else
      alternatives << statement
    end
  end
end
json.alternatives alternatives.each do |statement|
  json.partial! "statements/uri", statement: statement
end
