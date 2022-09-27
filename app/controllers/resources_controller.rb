class ResourcesController < ApplicationController
    skip_before_action :verify_authenticity_token


  def index
    @resources = {}
    @resources["event"] = helpers.get_uris params[:seedurl], "Event"
    @resources["place"] =  helpers.get_uris params[:seedurl], "Place"
    @resources["organization"] =  helpers.get_uris params[:seedurl], "Organisation"
    @resources["person"] =  helpers.get_uris params[:seedurl], "Person"
    @resources["resource_list"] =  helpers.get_uris params[:seedurl], "ResourceList"
  end

  #GET /resources/:rdf_uri
  def show
    # get resource by rdf_uri and all statements for all related webpages
    @resource = Resource.new(params[:rdf_uri])
    @statement_keys =  @resource.statements.keys.sort
  end

  #POST /resources.json
  # Create a new resouces with URI (fake webpage) and statements.
  # options: 
  # rdfs_class:"Place", seedurl: "fass-ca",
  # statements: { "name"=> [{value: "name string", language: "en"}], "address"=>[{value: "address string"}],"same_as"=>[{value: "same as string"}]
  def create_resource
    minted_uri = "footlight:#{SecureRandom.uuid}" 
    @resource = Resource.new(minted_uri)
    @resource.rdfs_class = params[:rdfs_class]
    @resource.seedurl = params[:seedurl]
    if @resource.save(params[:statements])
      render :show, status: :created

    else
      # failed to create resource, so delete fake webpage
      render json: @resource.errors, status: :unprocessable_entity
    end
  end

  #GET /resources/:rdf_uri/webpage_urls
  def webpage_urls
    #this is used by Huginn to get the pages to rescrape based on upcoming event URIs
    if params[:rdf_uri]
      @urls = Webpage.where(rdf_uri: params[:rdf_uri])
      render :webpage_urls, formats: :json
    end
  end

  # DELETE /resources/:rdf_uri
  def destroy
    webpages = Webpage.where(rdf_uri: params[:rdf_uri])
    webpages.each do |webpage|
      webpage.destroy
    end
    respond_to do |format|
      format.html { redirect_to "/websites/events", notice: 'Resource was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  # PATCH /resources/:rdf_uri/archive
  def archive
      review_all_statements params[:rdf_uri], params[:event][:status_origin]
      webpages = Webpage.where(rdf_uri: params[:rdf_uri])

      webpages.each do |webpage|
        webpage.update(archive_date: Time.now - 1.day)
      end

      respond_to do |format|
        format.html { redirect_to "/websites/events", notice: 'Event was successfully archived.' }
        format.json { head :no_content }
      end
  end


  # PATCH /resources/:rdf_uri/reviewed_all
  # Used by Footlight Client
  def reviewed_all

    # OLD: review_all_statements params[:rdf_uri], params[:event][:status_origin]
    Resource.new(params[:rdf_uri]).review_all_resource_except_flagged(params[:event][:status_origin])

    uri_to_load = params[:rdf_uri]
    if params[:review_next] == "true"
      #get next rdf_uri
      uris_to_review = Statement.joins({webpage: :website},:source, {webpage: :rdfs_class})
        .where(webpages:{websites: {seedurl: params[:seedurl]}, rdfs_classes: {name: "Event"}})
        .where(sources: {selected: true})
        .where(status: "initial")
        .or(Statement.joins({webpage: :website}, :source, {webpage: :rdfs_class})
        .where(webpages: {websites: {seedurl: params[:seedurl]}, rdfs_classes: {name: "Event"}})
        .where(sources: {selected: true})
        .where(status: "updated"))
        .order(:created_at)
        .pluck(:rdf_uri)
        .uniq
      if !uris_to_review.blank?
        uri_to_load = uris_to_review.first
      end
    end
    respond_to do |format|
      format.html { redirect_to show_resources_path(rdf_uri: uri_to_load, format: :html) }
      format.json { redirect_to show_resources_path(rdf_uri: uri_to_load, format: :json)}
    end
  end




end
