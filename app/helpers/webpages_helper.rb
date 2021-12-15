# Helper used in mulitple places
module WebpagesHelper
  # Check for missing required properties
  # TODO: replace this with SHACL
  def missing_required_properties(event_statement_collection)
    # receive a set of statements for an event and check if the event is publishable
    mandatory_schema = ["http://schema.org/name", "http://schema.org/startDate", "http://schema.org/location"]
    problem_statements = event_statement_collection.select{ |s|  mandatory_schema.include?(s['uri']) && (( s['status'] != "ok" && s['status']  != "updated")  || s['value'] == "[]" ||  s['value'].blank? ) }

    # Virtual Location removes location error if valid
    if event_statement_collection.select { |s| s['label'] == "Virtual Location" && (( s['status'] == "ok" || s['status']  == "updated")  && s['value'] != "[]" &&  !s['value'].blank? )}
      problem_statements.reject! { |s| s['uri'] == "http://schema.org/location" }
    end

    problem_statements
  end
end
