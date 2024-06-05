module ResourcesHelper
  include StatementsHelper

  def get_uris seedurl, rdfs_class_name
    uri_list = []
    website = Website.where(seedurl: seedurl).includes(:webpages).first
    if !website.nil?
      rdfs_class = RdfsClass.where(name: rdfs_class_name).first
      uri_list = website.webpages.where(rdfs_class: rdfs_class).pluck(:rdf_uri).uniq
      name_properties = Property.where(label: "Name")
      uri_list.map!{ |uri| {uri: uri, name: Statement.includes(:source).where(webpage: Webpage.where(rdf_uri: uri).first, sources: { property: name_properties }).first&.cache}}
    end
    return uri_list
  end


  # Pass in an ActiveRecord statement  
  # to build a statements hash { "prop_1": {value: "",...}, "prop_2": {value: "",...}}
  # with nested alternatives and using selected inviduals.
  # Note: must sort by selected invidiuals so that will be added first
  # output statements hash: 
  #  { "webpage_link_fr" : {
  #     "subject": "adr:spec-qc-ca_chaakapesh",
  #     "webpage_class_name" : "Event",
  #     "id": 84138,
  #     "status": "ok",
  #     "status_origin": "Gregory Saumier-Finch",
  #     "cache_refreshed": "2021-12-09T23:09:48.457Z",
  #     "cache_changed": null,
  #     "source_id": 691,
  #     "webpage_id": 5667,
  #     "created_at": "2021-02-05T09:04:29.085Z",
  #     "updated_at": "2021-12-09T23:09:48.462Z",
  #     "selected_individual": false,
  #     "value": "https://spec.qc.ca/spectacle/chaakapesh",
  #     "label": "Webpage link",
  #     "language": "fr",
  #     "source_label": "",
  #     "datatype": "",
  #     "expected_class": "",
  #     "uri": "http://schema.org/url",
  #     "manual": false,
  #     "rdf_uri": "adr:spec-qc-ca_chaakapesh",
  #     "alternatives": [{}]
  #     }
  #  }
  def build_nested_statement(statements, statement, subject:, webpage_class_name: )
    property = build_key(statement) # StatementsHelper
    statements[property] = {} if statements[property].nil?
    # add statements that are 'not selected' as an alternative inside the selected statement
    if statement.selected_individual
      if statements[property]["id"].present?
        statements[property].merge!(status: "problem", "value": "Duplicate selected properties: #{statements[property]["id"]} and #{statement.id}") 
      else
        statements[property].merge!(adjust_labels_for_api(statement, subject: subject, webpage_class_name: webpage_class_name )) # ResourcesHelper
      end
    else
      statements[property].merge!({alternatives: []}) if statements[property][:alternatives].nil?
      statements[property][:alternatives] << adjust_labels_for_api(statement, subject: subject, webpage_class_name: webpage_class_name) # ResourcesHelper
    end
    return statements
  end


  # input: ActiveRecord statement, :subject, :webpage_class_name
  # output: Hash
  def adjust_labels_for_api statement, **extras
    
    #convert ActiveRecord to hash despite the misleading name of .as_json
    json_statement = statement.as_json 

    #replace "cache" with "value" for better API read-ability
    json_statement[:value] = statement.cache
    json_statement.delete("cache")

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
    json_statement[:manual] = statement.manual
    json_statement[:source_is_feed] = statement.source.algorithm_value.start_with?("manual=") ? false : true
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
