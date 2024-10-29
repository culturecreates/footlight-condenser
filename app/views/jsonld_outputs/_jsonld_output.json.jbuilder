json.extract! jsonld_output, :id, :name, :frame,  :created_at, :updated_at
json.url jsonld_output_url(jsonld_output, format: :json)
