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
        "@id": "#{webpage.rdf_uri}"
        }


      _condensor_statements.each do |statement|
        if statement.source.selected == true  && (statement.status == "ok" || statement.status == "updated")  && (statement.source.language == _lang || statement.source.language == "")
          prop = statement.source.property.uri.to_s.split("/").last

          if prop != nil
            if statement.source.property.value_datatype == "xsd:anyURI"
              begin
                uri_object = JSON.parse(statement.cache)
                _jsonld[prop] = {"@type": uri_object[1], "name": uri_object[2][0], "@id": uri_object[2][1]}
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
      location = helpers.get_kg_place _jsonld["location"][:@id]  if _jsonld["location"]
      if !location.blank?
        _jsonld["location"]["address"] = {
              "@type": "PostalAddress",
              "streetAddress": location["streetAddress"],
              "addressCountry": location["addressCountry"],
              "addressLocality": location["addressLocality"],
              "addressRegion": location["addressRegion"],
              "postalCode": location["postalCode"]
            }
      end


      # REPLACE adr: with http://artsdata.ca/resource/
      _jsonld = eval(_jsonld.to_s.gsub(/adr:/,"http://artsdata.ca/resource/"))

      #creates seperate events per startDate
      ## MUST have startDate, location and name
      if (!_jsonld["startDate"].blank? && !_jsonld["location"].blank? && (!_jsonld["name"].blank? || !_jsonld["name_en"].blank? || !_jsonld["name_fr"].blank?))
        @events = []
        _jsonld["startDate"].each do |event_startDate|
          event =  _jsonld.dup
          event["startDate"] = event_startDate
          @events << event
        end
      else
        @events = ["Mandatory Event fields need review: title, location, startDate"]
      end

      render :event_markup, formats: :json
    end
  end
end
