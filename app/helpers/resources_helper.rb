module ResourcesHelper

  def get_uris seedurl, rdfs_class_name
    uri_list = []
    website = Website.where(seedurl: seedurl).includes(:webpages).first
    if !website.nil?
      rdfs_class = RdfsClass.where(name: rdfs_class_name).first
      uri_list = website.webpages.where(rdfs_class: rdfs_class).pluck(:rdf_uri).uniq
    end
    return uri_list
  end

  def adjust_labels_for_api statement
    json_statement = JSON.parse(statement.to_json)
    #replace "cache" with "value" for better API read-ability
    
    if statement.source.property.value_datatype == "xsd:anyURI"
      json_statement["value"] = JsonUriWrapper.build_json_from_anyURI statement.cache 
    else
      json_statement["value"] = statement.cache
    end
    json_statement.delete("cache")

    json_statement["label"] = statement.source.property.label
    json_statement["language"] = statement.source.language
    json_statement["source_label"] = statement.source.label
    json_statement["datatype"] = statement.source.property.value_datatype
    json_statement["expected_class"] = statement.source.property.expected_class
    json_statement["uri"] = statement.source.property.uri

    json_statement["manual"] = statement.source.algorithm_value.start_with?("manual=") ? true : false
    json_statement["selected_source"] = statement.source.selected
    return json_statement
  end


  def calculate_resource_status statements
    resource_status = {initial:0, missing:0, ok: 0, updated:0, problem: 0}
    statements.each do |s|
      resource_status[s.status] = 0 if resource_status[s.status].nil?
      resource_status[s.status] += 1 if s.source.selected?
    end
    return resource_status
  end
end
