module JsonUtilities
  # Recursively normalizes JSON-like structures for robust equality comparison.
  # - Converts all hash keys to strings
  # - Removes "created_at" and "updated_at" keys at any depth
  # - Recursively sorts hashes (key order doesn't matter)
  # - Leaves arrays order-sensitive (Ruby/JSON spec)
  def self.deep_normalize(obj)
    case obj
    when Hash
      obj.each_with_object({}) do |(k, v), result|
        key = k.to_s
        next if key == "created_at" || key == "updated_at"
        result[key] = deep_normalize(v)
      end.sort.to_h # sort keys so hash order doesn't matter
    when Array
      obj.map { |e| deep_normalize(e) }
    else
      obj
    end
  end

  # Robust, order-insensitive comparison of two JSON-like objects.
  # Accepts Ruby Hash, Array, or JSON string.
  def self.compare_json(json1, json2)
	allowed_types = [Hash, Array]

	# Parse JSON if needed, rescue parse errors
	begin
      json1 = JSON.parse(json1) if json1.is_a?(String)
	  json2 = JSON.parse(json2) if json2.is_a?(String)
	rescue JSON::ParserError
	  return false
	end

	return false unless allowed_types.include?(json1.class) && allowed_types.include?(json2.class)
	return false unless json1.class == json2.class

	deep_normalize(json1) == deep_normalize(json2)
  end

end
