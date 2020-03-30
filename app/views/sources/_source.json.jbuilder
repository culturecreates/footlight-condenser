json.extract! source, :id, :algorithm_value, :label, :language, :selected, :selected_by, :next_step, :render_js, :property_id, :website_id, :created_at, :updated_at
json.url source_url(source, format: :json)
json.property source.property.label
json.domain source.property.rdfs_class.name