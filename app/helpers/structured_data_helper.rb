module StructuredDataHelper
  include CcKgHelper

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
    ## MUST have startDate, location and name
    if (!_jsonld["startDate"].blank? && !_jsonld["location"].blank? && (!_jsonld["name"].blank? || !_jsonld["name_en"].blank? || !_jsonld["name_fr"].blank?))
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




  def build_events_per_startDate _jsonld
    events = []
    dates = _jsonld["startDate"]
    locations = _jsonld["location"]
    durations = _jsonld["duration"]
    offer_urls = _jsonld[:offers]["url"]  if _jsonld[:offers]

    dates.each_with_index do |date,index|
      event =  _jsonld.dup
      event["startDate"] = date

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
      jsonld[:offers]["validFrom"] =  Date.today.to_s(:iso8601)
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
      # Handle 2 possible data structres by making both into a list of arrays.
      #1: [["source 1","Place",["place name","adr:palce_uri"]],[]]
      #2: ["source 1","Place",["place name","adr:palce_uri"]]
      if !uri_statement.starts_with?("[[")
        uri_statement = "[#{uri_statement}]"
      end
      uri_object = JSON.parse(uri_statement)
      jsonld[prop] = []
      uri_object.each do |uri_object|
        jsonld[prop] << {"@type": uri_object[1], "name": uri_object[2][0], "@id": uri_object[2][1]}
      end
    rescue
      puts "ERROR making JSON-LD parsing property #{prop} statement.cache: #{uri_statement}"
    end
    return jsonld
  end




  def add_location

          #add location address
          # location = helpers.get_kg_place _jsonld["location"][:@id]  if _jsonld["location"]
          # if !location.blank?
          #   _jsonld["location"]["address"] = {
          #         "@type": "PostalAddress",
          #         "streetAddress": location["streetAddress"],
          #         "addressCountry": location["addressCountry"],
          #         "addressLocality": location["addressLocality"],
          #         "addressRegion": location["addressRegion"],
          #         "postalCode": location["postalCode"]
          #       }
          # end
  end

  def get_kg_place place_uri

    if place_uri[0..3] == "http"
      place_uri = "<#{place_uri}>"
    elsif place_uri[0..3] == "adr:"
      place_uri = "<http://artsdata.ca/resource/#{place_uri[4..-1]}>"
    end


    q = "SELECT ?pred ?obj where {    \
         #{place_uri} ?a ?b   .  \
         ?b  a  <http://schema.org/PostalAddress> .   \
         ?b  ?pred ?obj .    \
         }"
    results = cc_kg_query(q, place_uri)

    if results[:error].blank?
      place = {}
      results[:data].each do |statement|
        place[statement["pred"]["value"].to_s.split('/').last] =  statement["obj"]["value"]
      end
    else
      place = {:error => results[:error]}
    end
    return place
  end

  def make_into_array str
    if str[0] != "["
      array = [] << str
    else
      array = JSON.parse(str)
    end
    return array
  end

end
