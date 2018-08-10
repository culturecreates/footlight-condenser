module ResourcesHelper

  def get_uris seedurl, rdfs_class_name
    uri_list = []
    website = Website.where(seedurl: seedurl).first
    if !website.nil?
      rdfs_class = RdfsClass.where(name: rdfs_class_name).first
      webpages = website.webpages.where(rdfs_class: rdfs_class)
      webpages.each {|page| uri_list << {rdf_uri: page.rdf_uri}}
      uri_list.uniq!
    end
    return uri_list
  end

  def adjust_labels_for_api statement
    json_statement = JSON.parse(statement.to_json)
    #replace "cache" with "value" for better API read-ability
    json_statement["value"] = json_statement.delete("cache")
    json_statement["label"] = statement.source.property.label
    json_statement["language"] = statement.source.language
    json_statement["datatype"] = statement.source.property.value_datatype
    json_statement["manual"] = statement.source.algorithm_value.start_with?("manual=") ? true : false
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
