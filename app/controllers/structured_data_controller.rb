class StructuredDataController < ApplicationController


  def place_markup
    #TODO: add route and code to create JSON-LD for Places
  end

  # GET /structured_data/event_markup?url=
  def event_markup
    params[:url]
    params[:adr_prefix] ||= "http://artsdata.ca/resource/"
    webpage = Webpage.where(url: params[:url]).first

    if webpage.blank?
      render json: {error: "No condensor webpage: #{params[:url]}"}, status: :unprocessable_entity
    else
      lang = webpage.language
      condensor_statements = []
      webpages = Webpage.where(rdf_uri: webpage.rdf_uri)
      webpages.each do |w|
        w.statements.each do |s|
          condensor_statements << s
        end
      end

      @events = helpers.build_jsonld  condensor_statements, lang, webpage.rdf_uri,   params[:adr_prefix]

      if @events
        render :event_markup, formats: :json
      else
        render json: {error: "Mandatory Event fields need review: title, location, startDate for #{webpage.rdf_uri}"}, status: :unprocessable_entity
      end

    end
  end


end
