# Class to wrap the Condenser data type xsd:anyURI in JSON
# and convert from a string stored in the database
class JsonUriWrapper
  # Extract only the URIs from the linked data stored in the cache property
  # Condenser stores linked data as:
  # {search: "source text", class: "Expected Class", links: [ {label: "Entity label",uri: "URI" }] }

  def self.extract_uris_from_cache(cache)
    return [] if cache.blank?
    cache_obj = build_json_from_anyURI(cache)
    uris = []
    deleted_uris = []
    # Extract the links from all except where search: "Manually Deleted"
    cache_obj.each do |item|
      if item[:search] != 'Manually deleted'
        uris << item[:links].flatten.pluck(:uri)
      else
        deleted_uris << item[:links].flatten.pluck(:uri)
      end
    end
    uris.flatten - deleted_uris.flatten
  end

  def self.check_for_multiple_missing_links(cache)
    cache_obj = build_json_from_anyURI(cache)
    uris = []
    cache_obj.each do |item|
      if item[:search] != 'Manually deleted' && item[:search] != 'Manually added'
        uris << item[:links].flatten.pluck(:uri) 
      end
    end
    if uris.flatten.empty? 
      # allow manually added place when all others are missing
      manual = cache_obj.select { |item| item[:search] ==  'Manually added' }.first
      if manual 
        return false if !invalid_uri?(manual[:links].first[:uri])
      end
      true 
    else
      # check that all uris are valid
      uris.each do |uri|
        return true if invalid_uri?(uri.first)
      end
      false
    end
  end

  def self.invalid_uri?(uri)
    uri.blank? || !( uri.starts_with?('http') || uri.starts_with?('footlight:') )
  end

  def self.build_json_from_anyURI(cache_str)
    return [] if cache_str.blank?
    return cache_str unless cache_str.class == String
    begin
      value_array = JSON.parse(cache_str)
    rescue 
      value_array = []
    end

    value_obj = []
    if value_array.present?
      if value_array[0].class == String
        value_obj << sub_build_json_from_anyURI(value_array)
      else
        value_array.each do |obj|
          if obj.present?
            value_obj << sub_build_json_from_anyURI(obj)
          end
        end
      end
    end
    return value_obj
  end

  def self.sub_build_json_from_anyURI(value_array)
    value_obj = {search: value_array[0], class: value_array[1]}
    hits = []
    if value_array[2..-1]
      value_array[2..-1].each do |hit|
        if !hit.include?("abort")
          hits << { label: hit[0], uri: hit[1]}
        end
      end
    end
    value_obj[:links] = hits
    return value_obj
  end
end
