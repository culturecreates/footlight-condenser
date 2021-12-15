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

  # input: ActiveRecord statement, :subject, :webpage_class_name
  # output: Hash
  def adjust_labels_for_api statement, **extras
    
    #convert ActiveRecord to hash despite the misleading name of .as_json
    json_statement = statement.as_json 

    #replace "cache" with "value" for better API read-ability
    json_statement[:value] = statement.cache
    json_statement.delete(:cache)

    json_statement[:datatype] = statement.source.property.value_datatype
    if json_statement[:datatype] == "xsd:anyURI"
      json_statement[:value] = JsonUriWrapper.build_json_from_anyURI(json_statement[:value])
    end
   
    json_statement[:subject] = extras[:subject] if extras
    json_statement[:webpage_class_name] = extras[:webpage_class_name] if extras
    json_statement[:label] = statement.source.property.label
    json_statement[:language] = statement.source.language
    json_statement[:source_label] = statement.source.label
    json_statement[:datatype] = statement.source.property.value_datatype
    json_statement[:expected_class] = statement.source.property.expected_class
    json_statement[:predicate] = statement.source.property.uri
    json_statement[:manual] = statement.source.algorithm_value.start_with?("manual=") ? true : false
    json_statement[:selected_source] = statement.source.selected

    json_statement[:rdfs_class_name] = statement.source.property.rdfs_class.name
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
