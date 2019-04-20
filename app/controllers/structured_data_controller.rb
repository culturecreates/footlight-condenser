class StructuredDataController < ApplicationController

  # GET /structured_data/markup?url=
  def webpage
    params[:url]
    params[:adr_prefix] ||= "http://artsdata.ca/resource/"


    webpage = Webpage.where(url: params[:url]).first
    if webpage
      main_rdfs_class = webpage.rdfs_class
      condensor_statements = webpage.statements

      @data = {
        "webpage" => webpage,
        "rdfs_class" => main_rdfs_class,
        "adr_prefix" => params[:adr_prefix],

        "json-ld" => helpers.build_webpage_jsonld(main_rdfs_class, condensor_statements, webpage.language, webpage.rdf_uri, params[:adr_prefix])
      }
    end

    if @data
      render :webpage, formats: :json
    else
      render json: {error: "Error generating json-ld for webpage #{params[:webpage]}."}, status: :unprocessable_entity
    end
  end


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
      if  webpage.website.seedurl == "canadianstage-com"
        @events = helpers.build_jsonld_canadianstage  condensor_statements, lang, webpage.rdf_uri,   params[:adr_prefix]
      else
        @events = helpers.build_jsonld  condensor_statements, lang, webpage.rdf_uri,   params[:adr_prefix]
      end

      if @events
        render :event_markup, formats: :json
      else
        render json: {error: "Mandatory Event fields need review: title, location, startDate for #{webpage.rdf_uri}"}, status: :unprocessable_entity
      end

    end
  end


end
