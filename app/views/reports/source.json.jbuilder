json.array! @statements do | statement |
    json.merge! adjust_labels_for_api(statement)
    json.event_title  @filtered_event_titles[statement["webpage_id"]]
    json.event_archive_date @filtered_archive_dates[statement["webpage_id"]]
    json.rdf_uri @filtered_event_uris[statement["webpage_id"]]
end