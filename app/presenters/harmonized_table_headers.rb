module HarmonizedTableHeaders
  module_function

  def events
    [
      { label: "Title", sort_key: "title" },
      { label: "Date", sort_key: "date" },
      { label: "Archive date", sort_key: "archive_date" },
      { label: "Status" },
      { label: "Actions" }
    ]
  end

  def resources
    [
      { label: "Rdf uri", sort_key: "rdf_uri" },
      { label: "Class", sort_key: "rdfs_class_name" },
      { label: "Name", sort_key: "name" },
      { label: "Archive date", sort_key: "archive_date" },
      { label: "Actions" }
    ]
  end

  def sources
    [
      { label: "Status", sort_key: "selected" },
      { label: "Property / Language", sort_key: "language" },
      { label: "Pipeline", sort_key: "algorithm_value" },
      { label: "Fetch strategy" },
      { label: "Impact" },
      { label: "Last test", sort_key: "updated_at" },
      { label: "Actions" }
    ]
  end

  def webpages(show_distillator_cache_column:)
    headers = [
      { label: "Id" },
      { label: "Rdfs class" },
      { label: "Lang", sort_key: "language" },
      { label: "Url", sort_key: "url" },
      { label: "Publishable" },
      { label: "Rdf uri" },
      { label: "Archive Date" },
      { label: "Updated", sort_key: "updated_at" },
      { label: "JSON-LD Output" },
      { label: "Active Cache" }
    ]
    headers << { label: "Condenser Cache" } if show_distillator_cache_column
    headers << { label: "Actions" }
    headers
  end

  def reports
    [
      { label: "Event title", sort_key: "event_title" },
      { label: "Cache", sort_key: "cache" },
      { label: "Webpage id", sort_key: "webpage_id" },
      { label: "Archive date", sort_key: "archive_date" },
      { label: "Rdf uri", sort_key: "rdf_uri" }
    ]
  end

  def places
    [
      { label: "Event Series URI", sort_key: "rdf_uri" },
      { label: "Based on", sort_key: "based_on" },
      { label: "Class" },
      { label: "Linked Name", sort_key: "linked_name" },
      { label: "Linked URI", sort_key: "linked_uri" }
    ]
  end

  def properties
    [
      { label: "ID", sort_key: "id" },
      { label: "Rdfs class", sort_key: "rdfs_class_id" },
      { label: "Label", sort_key: "label" },
      { label: "Value datatype", sort_key: "value_datatype" },
      { label: "Expected Class", sort_key: "expected_class" },
      { label: "Uri", sort_key: "uri" },
      { label: "Actions" }
    ]
  end

  def rdfs_classes
    [
      { label: "Name", sort_key: "name" },
      { label: "Actions" }
    ]
  end

  def statements(show_seedurl_col:)
    headers = [{ label: "Id", sort_key: "id" }]
    headers << { label: "Website" } if show_seedurl_col
    headers + [
      { label: "Property" },
      { label: "Source" },
      { label: "Cache", sort_key: "cache" },
      { label: "Status", sort_key: "status" },
      { label: "Manual", sort_key: "manual" },
      { label: "Selected Source" },
      { label: "Selected Individual", sort_key: "selected_individual" },
      { label: "Status origin" },
      { label: "Cache refreshed", sort_key: "cache_refreshed" },
      { label: "Cache changed", sort_key: "cache_changed" },
      { label: "Updated", sort_key: "updated_at" },
      { label: "Actions" }
    ]
  end
end
