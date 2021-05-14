json.extract! message, :id, :message, :artifact, :created_at, :updated_at
json.url message_url(message, format: :json)
