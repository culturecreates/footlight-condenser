module StructuredDataHelper
  include CcKgHelper


  def build_jsonld_for_class class_name, statements

    #using only selected and valid Statements build a Hash {property1 => [cache], property2 => [cache1, cache2]}
    converted_statements = {}
    statements.each do |statement|
      if statement.source.selected == true && prop = statement.source.property.uri.to_s.split("/").last
         if statement.source.property.value_datatype == "xsd:anyURI"
           #todo: case with multiple uris.["scrapped name","Class name", ["entity name","uri"],["entity name","uri"]]

           # expected format: ["scrapped name","Class name", ["entity name","uri"]]
           puts "statement.cache[2][1]: #{statement.cache[2][1]} from statement.cache: #{statement.cache} "
           converted_statements[prop] = make_into_array statement.cache[2][1]
         else
           converted_statements[prop] = make_into_array statement.cache
         end
      end
    end

    #get MAX length of all arrays in the value position of the hash
    max_instances = 1
    converted_statements.each do |n,v|
      max_instances = v.count if v.count > max_instances
    end

    # Create max_instances of JSON-LD class_name entities.
    # If a statement does not have multiple values, duplicate the first to match max_instances.
     jsonld = []
     max_instances.times do |index|
       jsonld[index] = {"@type" => class_name}
       converted_statements.each do |n,v|
           jsonld[index][n] = v[index] || v[0]
       end
     end

    return jsonld
  end

  def group_statements_by_class condensor_statements

    statements_grouped_by_class =  Hash.new {|h,k| h[k]=[]}
    condensor_statements.each do |statement|
      rdf_class = statement.source.property.rdfs_class
      statements_grouped_by_class[rdf_class.name] << statement
    end
    return statements_grouped_by_class
  end


  def nest_jsonld main_json, insert_json, property
    main_json_list = make_into_array main_json
    insert_json_list =  make_into_array insert_json

    main_json_list.each_with_index  do |j,index|
          j[property] = insert_json_list[index]
    end

    return main_json_list
  end

  def build_webpage_jsonld main_rdfs_class, condensor_statements, language, rdf_uri, adr_prefix

    # step 1: Group statements by Class
    statements_grouped_by_class =   group_statements_by_class condensor_statements

    #create json-ld of each class
    jsonld_grouped_by_class =  Hash.new {|h,k| h[k]=[]}
    statements_grouped_by_class.each do |class_name, statements|
      jsonld_grouped_by_class[class_name] = build_jsonld_for_class class_name, statements
    end

    #link all classes by traversing the tree of classes in properties table
    # 1. for each class starting with main class
    # 2. look up subclases
    # 3. link them
     merge_classes main_rdfs_class, jsonld_grouped_by_class


    return _jsonld
  end

  def get_rdfs_class_leaves rdfs_class_name
    #checks if rdfs_class_name has nested classes: returns ActiveRecord::Relation array of properties
    properties = []
    classes = RdfsClass.where(name: rdfs_class_name)
    if classes.present?
      rdfs_class = classes.first
      properties = Property.where(rdfs_class: rdfs_class, value_datatype: "bnode")
    end
    return properties
  end


  def merge_classes (rdfs_class_name, entity_list)
    # find leaves which are classes linked through a property
    # entity_list: [Class Name 1: [{statement1}, {statement2}], Class Name 2: [{statement}]]

    leaves = get_rdfs_class_leaves rdfs_class_name # gets a list of properties linked to subClasses

    leaves.each do |leaf|

      leaf_uri_class = leaf.uri.to_s.split("/").last
      #check if leaf exists in the entity_list with statements to merge
      if entity_list[leaf_uri_class]

        #check if leaf has linked classes and recursively call merge_classes
        subleaves = get_rdfs_class_leaves leaf.expected_class
        if subleaves.present?
          merge_classes subleaves.expected_class, entity_list
        end
        entity_list[rdfs_class_name] = nest_jsonld entity_list[rdfs_class_name], entity_list[leaf.expected_class], leaf_uri_class
      end
    end
    return entity_list[rdfs_class_name]
  end


  def make_into_array input
    return input if input.class == Array
    return [input] if  input.class == Hash
    if input[0] != "["
      array = [] << input
    else
      array = JSON.parse(input)
    end
    return array
  end






  def build_jsonld_canadianstage condensor_statements, language, rdf_uri, adr_prefix
    _jsonld = {
      "@context": "http://schema.org",
      "@type": "Event",
      "workFeatured": {
        "@type": "CreativeWork",
        "@id": rdf_uri
      }
      }

    locations_to_add = []
    condensor_statements.each do |statement|
      if statement.source.selected == true  && (statement.status == "ok" || statement.status == "updated")  && (statement.source.language == language || statement.source.language == "")
        prop = statement.source.property.uri.to_s.split("/").last
        logger.info " ++++++++++++=Adding property #{prop}"
        if prop != nil
          if statement.source.property.value_datatype == "xsd:anyURI"

            if prop == "location"
              add_anyURI _jsonld, prop, statement.cache
              locations_to_add << _jsonld["location"][0][:@id] if !_jsonld["location"].blank?
            elsif prop == "CreativeWork:producer"
              data = JSON.parse(statement.cache)
              @creativework_producer = {"@type": "Organization","@id": data[2][1], "name":data[0]}
            else
              add_anyURI _jsonld, prop, statement.cache
            end
          elsif  statement.source.property.value_datatype == "xsd:dateTime"
            _jsonld[prop] = make_into_array statement.cache
            #add endDate here by adding duration or else removing the time and keeping only the date.
          elsif prop == "duration"
            duration_array = make_into_array statement.cache
            _jsonld["duration"] = []
            duration_array.each do |d|
              _jsonld["duration"] << d if d[0..1] == "PT" #needs to be in ISO8601 duration syntax to avoid adding "Duration not available"
            end
          elsif prop == "offer:url"
            add_offer _jsonld, "url", statement.cache
          elsif prop == "offer:price"
            add_offer _jsonld, "price", statement.cache
          elsif prop == "CreativeWork:keywords"
            add_keywords _jsonld, statement.cache
          elsif prop == "CreativeWork:video"
            add_video _jsonld, statement.cache
          elsif prop == "performer:url"
            add_performer _jsonld, "url", statement.cache
          else
            if prop == "name"
              @creativework_name = statement.cache
              prop = "#{prop}"
            end
            if prop == "description"
              @creativework_description = statement.cache
              prop = "#{prop}"
            end
            if prop == "url"
              @creativework_url = statement.cache
            end

            _jsonld[prop] = statement.cache
          end
        else
          logger.error "ERROR making JSON-LD: missing property uri for: #{statement.source.property.label}"
        end
      end
    end


    #creates seperate events per startDate each with location if there is a list of locations.
    ## MUST have startDate, location and name
    if (!_jsonld["startDate"].blank? && !_jsonld["location"].blank? && (!_jsonld["name"].blank? || !_jsonld["name_en"].blank? || !_jsonld["name_fr"].blank?))
      @events = build_events_per_startDate _jsonld

      #add a location entities
      locations_to_add.each do |location_uri|
        location = _jsonld["location"][0].clone
        location["@context"] = "http://schema.org"
        location["address"] = add_address(location_uri)
        @events <<  location
      end

      #add creative work
      @events << {
        "@context":  "http://schema.org",
        "@type": "CreativeWork",
        "@id": rdf_uri,
        "name": @creativework_name,
        "description": @creativework_description,
        "mainEntityOfPage": @creativework_url,
        "url": @creativework_url,
        "genre": "http://sparql.cwrc.ca/ontologies/genre#performance",
        "producer": @creativework_producer
      }

      # REPLACE adr: with complete URI
      adr_prefix ||= "http://graph.footlight.io/resource/"
      @events = eval(@events.to_s.gsub(/adr:/,adr_prefix))
    else
       @events = nil
    end
    return @events
  end

  def build_jsonld condensor_statements, language, rdf_uri, adr_prefix
    _jsonld = {
      "@context":
        {
          "@vocab": "http://schema.org",
          "description_en":{"@id": "description", "@language": "en"},
          "description_fr":{"@id": "description","@language": "fr"},
          "name_en":{"@id": "name",	"@language": "en"},
          "name_fr":{"@id": "name", "@language": "fr"}
        },
      "@type": "Event",
      "superEvent": { "@id": "#{rdf_uri}"}
      }

    condensor_statements.each do |statement|
      if statement.source.selected == true  && (statement.status == "ok" || statement.status == "updated")  && (statement.source.language == language || statement.source.language == "")
        prop = statement.source.property.uri.to_s.split("/").last
        if prop != nil
          if statement.source.property.value_datatype == "xsd:anyURI"
            add_anyURI _jsonld, prop, statement.cache
          elsif  statement.source.property.value_datatype == "xsd:dateTime"
            _jsonld[prop] = make_into_array statement.cache
          elsif prop == "duration"
            duration_array = make_into_array statement.cache
            _jsonld["duration"] = []
            duration_array.each do |d|
              _jsonld["duration"] << d if d[0..1] == "PT" #needs to be in ISO8601 duration syntax to avoid adding "Duration not available"
            end
          elsif prop == "offer:url"
            add_offer _jsonld, "url", statement.cache
          elsif prop == "offer:price"
            add_offer _jsonld, "price", statement.cache
          elsif prop == "CreativeWork:keywords"
            add_keywords _jsonld, statement.cache
          elsif prop == "CreativeWork:video"
            add_video _jsonld, statement.cache
          elsif prop == "performer:url"
            add_performer _jsonld, "url", statement.cache
          else
            if prop == "name" || prop == "description"
              prop = "#{prop}_#{language}"
            end
            _jsonld[prop] = statement.cache
          end
        else
          puts "ERROR making JSON-LD: missing property uri for: #{statement.source.property.label}"
        end
      end
    end


    #creates seperate events per startDate each with location is there is a list of locations.
    ## MUST have startDate, location, name and if multiple startDates the locations must be 1 or equal to the number of Locations.
    if publishable?(_jsonld)
      @events = build_events_per_startDate _jsonld

      # Add Event Series to include all events with the same CreativeWork (Name, description, event page)
      @events << {
        "@context":
          {
            "@vocab": "http://schema.org",
            "name_fr": {"@id": "name", "@language": "fr"},
            "name_en": {"@id": "name",	"@language": "en"}
          },
          "@type": "EventSeries",
           "@id": "#{rdf_uri}",
           "location":@events[0]["location"],
           "startDate": @events[0]["startDate"],
           "name_#{_jsonld['name_fr'] ? 'fr' : 'en'}": _jsonld["name_fr"] ||= _jsonld["name_en"]
          }

      # REPLACE adr: with complete URI
      adr_prefix ||= "http://graph.footlight.io/resource/"
      @events = eval(@events.to_s.gsub(/adr:/,adr_prefix))
    else
       @events = nil
    end
    return @events
  end



  def publishable? data
    return false if data["startDate"].blank?
    return false if data["location"].blank?
    return false if (data["name"].blank? && data["name_en"].blank? && data["name_fr"].blank?)

    #if there is more than 1 location then the locations and startDates must be equal and we assume they are mapped one to one.

    if data["location"].count > 1
      return false if data["location"].count != data["startDate"].count
    end

    return true
  end



  def build_events_per_startDate _jsonld
    events = []
    dates = _jsonld["startDate"]
    locations = _jsonld["location"]
    durations = _jsonld["duration"]
    offer_urls = _jsonld[:offers]["url"]  if _jsonld[:offers]

    dates.each_with_index do |date,index|
      event =  _jsonld.dup
      event["startDate"] = date
      event["endDate"] = Date.parse(date).to_s(:iso8601)

      #event["startDate"] = DateTime.parse(date).to_s(:iso8601)
     #event["endDate"] = (DateTime.parse(date) + 2.hours).to_s(:iso8601)


      ### handle single or multiple locations and durations per date. Must equal the count of dates.
      if !locations.blank?
        if  dates.count == locations.count
          event["location"] = locations[index]
        else
          event["location"] = locations[0]
        end
      end
      if !durations.blank?
        if dates.count == durations.count
          event["duration"] = durations[index]
        else
          event["duration"] = durations[0]
        end
      end
      if !offer_urls.blank?
        if dates.count == offer_urls.count
          event[:offers] = event[:offers].dup
          event[:offers]["url"] = offer_urls[index]
        else
          event[:offers]["url"] = offer_urls[0]
        end
      end
      events << event
    end
    return events
  end

  def add_offer jsonld, property, value

    if !jsonld[:offers]
      jsonld[:offers] = { "@type": "Offer" }
      jsonld[:offers]["validFrom"] =  (Date.today - 1.month).to_s(:iso8601)
      jsonld[:offers]["availability"] = "http://schema.org/InStock"
    end
    if property == "url"
      if value.include?("Complet")
        jsonld[:offers]["availability"] =  "http://schema.org/SoldOut"
      else
        jsonld[:offers]["url"] = []
        make_into_array(value).each do |v|
          jsonld[:offers]["url"] << v
        end
      end
    elsif property == "price" && !value.blank?
        jsonld[:offers]["price"] = value
        jsonld[:offers]["priceCurrency"] = "CAD"
    else
      logger.error ("*** Invalid property for schema.org/Offer: #{property} for JSON-LD: #{jsonld.inspect}")
    end
    return jsonld
  end

  def add_keywords jsonld, value
    #  Event:workPerformed:CreativeWork:keywords
    if !value.blank?
      if !jsonld[:workPerformed]
        jsonld[:workPerformed] = {"@type": "CreativeWork"}
      end
      jsonld[:workPerformed][:keywords] = value
    end
    return jsonld
  end

  def add_video jsonld, value
   #  Event:workPerformed:CreativeWork:video:VideoObject:url
    if !value.blank? && value != "[]"
      if !jsonld[:workPerformed]
        jsonld[:workPerformed] = {"@type": "CreativeWork"}
      end

      if !jsonld[:workPerformed][:video]
        jsonld[:workPerformed][:video] = {
            "@type": "VideoObject",
            "url": []
          }
      end
      make_into_array(value).each do |url|
        jsonld[:workPerformed][:video][:url] << url
      end
    end
    return jsonld
  end

  def add_performer jsonld, prop, value
    #  Event:performer:PerformingGroup:url
    if !value.blank? && value != "[]"
      if !jsonld[:performer]
        jsonld[:performer] = { "@type": "PerformingGroup" }
      end
      jsonld[:performer][prop] = value
    end
    return jsonld
  end

  def add_anyURI jsonld, prop, uri_statement
    begin
      # Handle data structure
      # ["source 1","Place",["place name","adr:place_uri"],[]]
      #
      # if !uri_statement.starts_with?("[[")
      #   uri_statement = "[#{uri_statement}]"
      # end
      uri_objects = JSON.parse(uri_statement)
      jsonld[prop] = []
      logger.info "***** #{uri_objects.inspect}"

      uri_objects[2..-1].each do |uri_object|
          logger.info "***** adding #{uri_object.inspect}"
        jsonld[prop] << {"@type": uri_objects[1], "name": uri_object[0], "@id": uri_object[1]}
      end
    rescue
        logger.error "ERROR making JSON-LD parsing property #{prop} statement.cache: #{uri_statement}"
    end
    return jsonld
  end




  def add_address location_id

      #add location address

      address = get_kg_place location_id
      if !address.blank?
         {
              "@type": "PostalAddress",
              "streetAddress": address["streetAddress"],
              "addressCountry": address["addressCountry"],
              "addressLocality": address["addressLocality"],
              "addressRegion": address["addressRegion"],
              "postalCode": address["postalCode"]
            }
      end

  end

  def get_kg_place place_uri
    if place_uri
      if place_uri[0..3] == "http"
        place_uri = "<#{place_uri}>"
      elsif place_uri[0..3] == "adr:"
        place_uri = "<http://kg.artsdata.ca/resource/#{place_uri[4..-1]}>"
      end


      q = "SELECT ?pred ?obj where {    \
           #{place_uri} ?a ?b   .  \
           ?b  a  <http://schema.org/PostalAddress> .   \
           ?b  ?pred ?obj .    \
           }"
      results = cc_kg_query(q, place_uri)
      if !results[:error]
        place = {}
        results[:data].each do |statement|
          place[statement["pred"]["value"].to_s.split('/').last] =  statement["obj"]["value"]
        end
      else
        place = {:error => results[:error]}
      end
      return place
    end
  end


end
