class ResourcesController < ApplicationController
    skip_before_action :verify_authenticity_token

  # GET /events
  # GET /events.json
  def index
    @resources = {}
    @resources["Event"] = helpers.get_uris params[:seedurl], "Event"
    @resources["Place"] =  helpers.get_uris params[:seedurl], "Place"
    @resources["Organisation"] =  helpers.get_uris params[:seedurl], "Organisation"
  end

  #GET /resources/:rdf_uri
  def show
    # get all statements for all webpages for rdf_uri
    @statements = []
    webpages = Webpage.where(rdf_uri: params[:rdf_uri])
    webpages.each do |webpage|
      webpage.statements.each do |statement|
        @statements << statement
      end
    end
    @statements.sort
  end


  # PATCH /resources/:rdf_uri/reviewed_all
  def reviewed_all
    @statements = []
    _webpages = Webpage.where(rdf_uri: params[:rdf_uri])
    _webpages.each do |webpage|
      webpage.statements.each do |statement|
        @statements << statement
      end
    end
    @statements.each do |statement|
      statement.status = "reviewed" if statement.source.selected
      statement.save
    end
    render :show

  end

end
