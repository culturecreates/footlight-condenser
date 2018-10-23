class StructuredDataController < ApplicationController

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
            "description_fr":{ "@id": "description","@language": "fr"},
            "name_en":{"@id": "name",	"@language": "en"},
      		  "name_fr":{"@id": "name", "@language": "fr"}
          },
        "@type": "Event",
        "superEvent": "#{webpage.rdf_uri}"
        }


      _condensor_statements.each do |statement|
        if statement.source.selected == true  && (statement.status == "ok" || statement.status == "updated")  && (statement.source.language == _lang || statement.source.language == "")
          prop = statement.source.property.uri.to_s.split("/").last

          if prop != nil
            if statement.source.property.value_datatype == "xsd:anyURI"
              begin
                _uri_statement = statement.cache
                # Handle 2 possible data structres by making both into a list of arrays.
                #1: [["source 1","Place",["place name","adr:palce_uri"]],[]]
                #2: ["source 1","Place",["place name","adr:palce_uri"]]
                if !_uri_statement.starts_with?("[[")
                  _uri_statement = "[#{_uri_statement}]"
                end
                uri_object = JSON.parse(_uri_statement)
                _jsonld[prop] = []
                uri_object.each do |uri_object|
                  _jsonld[prop] << {"@type": uri_object[1], "name": uri_object[2][0], "@id": uri_object[2][1]}
                end
              rescue
                puts "ERROR making JSON-LD parsing property #{prop} statement.cache: #{statement.cache}"
              end
            elsif  statement.source.property.value_datatype == "xsd:dateTime"
              _dateTime_array = statement.cache
              if _dateTime_array[0] != ("[" || "{")
                  _jsonld[prop] = [] << _dateTime_array
              else
                _jsonld[prop] = JSON.parse(_dateTime_array)
              end
            elsif prop == "offer:url"
              #add offers
              _jsonld["offers"] = {
                    "@type": "Offer",
                    "url": statement.cache,
                #    "availability": "",
                #    "price": "",
                #    "validFrom": ""
                    "priceCurrency": "CAD" }
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


      # REPLACE adr: with http://artsdata.ca/resource/
      _jsonld = eval(_jsonld.to_s.gsub(/adr:/,"http://artsdata.ca/resource/"))

      #creates seperate events per startDate each with location is there is a list of locations.
      ## MUST have startDate, location and name
      #TODO: Add locations

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

        @events << {
            "@context": "http://schema.org",
            "@type": "EventSeries",
             "@id": "#{webpage.rdf_uri}"
            }

        render :event_markup, formats: :json
      else
        render json: {error: "Mandatory Event fields need review: title, location, startDate for #{_jsonld[:@id]}"}, status: :unprocessable_entity
      end


    end
  end
end
