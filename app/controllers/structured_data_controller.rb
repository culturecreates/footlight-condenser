class StructuredDataController < ApplicationController


  def place_markup
    #TODO: add route and code to create JSON-LD for Places
  end

  # GET /structured_data/event_markup?url=
  def event_markup
    params[:url]
    webpage = Webpage.where(url: params[:url]).first

    if webpage.blank?
      render json: {error: "No condensor webpage: #{params[:url]}"}, status: :unprocessable_entity
    else
      _lang = webpage.language
      _condensor_statements = []
      webpages = Webpage.where(rdf_uri: webpage.rdf_uri)
      webpages.each do |w|
        w.statements.each do |s|
          _condensor_statements << s
        end
      end
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
        "superEvent": { "@id": "#{webpage.rdf_uri}"}
        }

      _condensor_statements.each do |statement|
        if statement.source.selected == true  && (statement.status == "ok" || statement.status == "updated")  && (statement.source.language == _lang || statement.source.language == "")
          prop = statement.source.property.uri.to_s.split("/").last
          if prop != nil
            if statement.source.property.value_datatype == "xsd:anyURI"
              add_anyURI _jsonld, prop, statement.cache
            elsif  statement.source.property.value_datatype == "xsd:dateTime"
              add_dateTime  _jsonld, prop, statement.cache
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
                prop = "#{prop}_#{_lang}"
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
        @events = []
        dates = _jsonld["startDate"]
        locations = _jsonld["location"]
        dates.each_with_index do |date,index|
          event =  _jsonld.dup
          event["startDate"] = date
          if dates.count == locations.count
            event["location"] = locations[index]
          else
            event["location"] = locations[0]
          end
          @events << event
        end

        # Add Event Series to include all events with the same CreativeWork (Name, description, event page)
        @events << {
          "@context":
            {
              "@vocab": "http://schema.org",
              "name_fr":{"@id": "name", "@language": "fr"}
            },
            "@type": "EventSeries",
             "@id": "#{webpage.rdf_uri}",
             "location":locations[0],
             "startDate": dates[0],
             "name_fr": _jsonld["name_fr"]
            }

        # REPLACE adr: with URI
        @events = eval(@events.to_s.gsub(/adr:/,"http://laval.footlight.io/resource/"))

        render :event_markup, formats: :json
      else
        render json: {error: "Mandatory Event fields need review: title, location, startDate for #{_jsonld[:@id]}"}, status: :unprocessable_entity
      end


    end
  end

  private
    def add_offer jsonld, property, value
      if !jsonld[:offers]
        jsonld[:offers] = {
                        "@type": "Offer",
                        "url": "",
                        "availability": "http://schema.org/InStock",
                        "price": "",
                        "validFrom": Date.today.to_s(:iso8601),   #Today's date
                        "priceCurrency": "CAD" }
      end
      if property == "url" || property == "price"
        jsonld[:offers][property] = value
      else
          logger.error ("*** Invalid property for schema.org/Offer: #{property} for JSON-LD: #{jsonld.inspect}")
      end
      return jsonld
    end

    def add_keywords jsonld, value
      #  Event:workPerformed:CreativeWork:keywords
      if !jsonld[:workPerformed]
        jsonld[:workPerformed] = {"@type": "CreativeWork"}
      end
      jsonld[:workPerformed][:keywords] = value
      return jsonld
    end

    def add_video jsonld, value
     #  Event:workPerformed:CreativeWork:video:VideoObject:url
      if !jsonld[:workPerformed]
        jsonld[:workPerformed] = {"@type": "CreativeWork"}
      end

      if !jsonld[:workPerformed][:video]
        jsonld[:workPerformed][:video] = {
            "@type": "VideoObject",
            "url": []
          }
      end
      jsonld[:workPerformed][:video][:url] << value
      return jsonld
    end

    def add_performer jsonld, prop,value
      #  Event:performer:PerformingGroup:url
       if !jsonld[:performer]
         jsonld[:performer] = { "@type": "PerformingGroup" }
       end
       jsonld[:performer][prop] = value
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

    def add_dateTime   jsonld, prop, dateTime_array
      if dateTime_array[0] != ("[" || "{")
          jsonld[prop] = [] << dateTime_array
      else
        jsonld[prop] = JSON.parse(dateTime_array)
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
end
