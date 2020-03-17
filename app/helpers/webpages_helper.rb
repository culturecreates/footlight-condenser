module WebpagesHelper
    def missing_required_properties event_statement_collection
        #receive a set of statements for an event and check if the event is publishable
        mandatory_schema = ["http://schema.org/name", "http://schema.org/startDate", "http://schema.org/location"]
        problem_statements = event_statement_collection.select{ |s|  mandatory_schema.include?(s.source.property.uri) && (( s.status != "ok" && s.status  != "updated")  || s.cache == "[]" ||  s.cache.blank? ) }
    end
end
