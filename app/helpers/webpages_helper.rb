# Helper used in mulitple places
module WebpagesHelper
  # Check for missing required properties
  # TODO: replace this with SHACL
  def missing_required_properties(event_statement_collection)
    # receive a set of statements for an event and check if the event is publishable
    mandatory_schema = ["http://schema.org/name", "http://schema.org/startDate", "http://schema.org/location"]
    problem_statements = event_statement_collection.select{ |s| s[:rdfs_class_name] == "Event" && mandatory_schema.include?(s[:predicate]) && (( s['status'] != "ok" && s['status']  != "updated")  || s[:value] == "[]" ||  s[:value].blank? ) }

    # Virtual Location removes location error if valid
    if event_statement_collection.select { |s| s[:label] == "VirtualLocation" && (( s['status'] == "ok" || s['status']  == "updated")  && s[:value] != "[]" &&  s[:value].present? )}.count > 0
      problem_statements.reject! { |s| s[:predicate] == "http://schema.org/location" }
    end

    problem_statements
  end
end
