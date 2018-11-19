json.extract! webpage, :id, :url, :language, :rdf_uri, :rdfs_class_id, :archive_date, :website_id, :created_at, :updated_at
json.publishable @publishable[webpage.id]
