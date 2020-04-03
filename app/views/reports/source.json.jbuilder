json.array! @statements do | statement |
    json.merge! adjust_labels_for_api(statement)
    json.event_title @event_titles.select{ |t| t["webpage_id"] == statement["webpage_id"] }.first.cache
    json.event_archive_date @archive_dates.select{ |t| t.id == statement["webpage_id"] }.first.archive_date
end