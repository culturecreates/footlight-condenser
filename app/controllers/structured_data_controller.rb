class StructuredDataController < ApplicationController
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

      _jsonld = {"@context": "http://schema.org", "@type": "Event"}
      _condensor_statements.each do |statement|
        if statement.source.selected == true  && (statement.status == "ok" || statement.status == "updated")  && (statement.source.language == _lang || statement.source.language == "")
          prop = statement.source.property.uri.to_s.split("/").last
          if statement.source.property.value_datatype == "xsd:anyURI"
            uri_object = JSON.parse(statement.cache)
            _jsonld[prop] = {"@type": uri_object[1], "name": uri_object[2][0], "@id": uri_object[2][1]}
          elsif  statement.source.property.value_datatype == "xsd:dateTime"
            _jsonld[prop] = JSON.parse(statement.cache)
          elsif prop == "offer:url"
            #add offers
            _jsonld["offers"] = {
                  "@type": "Offer",
                  "url": statement.cache
                }
          else
            _jsonld[prop] = statement.cache
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


      #creates seperate events per startDate
      if !_jsonld["startDate"].blank?
        @events = []
        _jsonld["startDate"].each do |event_startDate|
          event =  _jsonld.dup
          event["startDate"] = event_startDate
          @events << event
        end
      end
      render :event_markup, formats: :json
    end
  end
end
