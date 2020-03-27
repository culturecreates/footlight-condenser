class ResourcesController < ApplicationController
    skip_before_action :verify_authenticity_token


  def index
    @resources = {}
    @resources["event"] = helpers.get_uris params[:seedurl], "Event"
    @resources["place"] =  helpers.get_uris params[:seedurl], "Place"
    @resources["organization"] =  helpers.get_uris params[:seedurl], "Organisation"
  end

  #GET /resources/:rdf_uri
  def show
    # get resource by rdf_uri and all statements for all related webpages
    @resource = { uri: params[:rdf_uri],
                  rdfs_class: "",
                  seedurl: "",
                  archive_date: "",
                  statements: {}}

    webpages = Webpage.where(rdf_uri: params[:rdf_uri])
    @resource[:rdfs_class] = webpages.first.rdfs_class.name if !webpages.empty?
   @resource[:seedurl] = webpages.first.website.seedurl if !webpages.empty?
   @resource[:archive_date] = webpages.last.archive_date if !webpages.empty?

    webpages.each do |webpage|
      webpage.statements.each do |statement|
        property = helpers.build_key(statement)
        @resource[:statements][property] = {} if @resource[:statements][property].nil?
        #add statements that are 'not selected' as an alternative inside the selected statement
        if statement.source.selected
          @resource[:statements][property].merge!(helpers.adjust_labels_for_api(statement))
        else
          @resource[:statements][property].merge!({alternatives: []}) if @resource[:statements][property][:alternatives].nil?
          @resource[:statements][property][:alternatives] << helpers.adjust_labels_for_api(statement)
        end
      end
    end
    @statement_keys = @resource[:statements].keys.sort
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
      format.html { redirect_to "/websites/events", notice: 'Event was successfully destroyed.' }
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
  def reviewed_all

    review_all_statements params[:rdf_uri], params[:event][:status_origin]

  #  update_remote_jsonld  params[:rdf_uri] #stored in wringer and updated in clouddb by wringer

    uri_to_load = params[:rdf_uri]
    if params[:review_next] == "true"
      #get next rdf_uri
      uris_to_review = Statement.joins({webpage: :website},:source, {webpage: :rdfs_class}).where(webpages:{websites: {seedurl: params[:seedurl]}, rdfs_classes: {name: "Event"}}).where(sources: {selected: true}).where(status: "initial").or(Statement.joins({webpage: :website}, :source, {webpage: :rdfs_class}).where(webpages: {websites: {seedurl: params[:seedurl]}, rdfs_classes: {name: "Event"}}).where(sources: {selected: true}).where(status: "updated")).order(:created_at).pluck(:rdf_uri).uniq
      if !uris_to_review.blank?
        uri_to_load = uris_to_review.first
      end
    end
    respond_to do |format|
      format.html { redirect_to show_resources_path(rdf_uri: uri_to_load, format: :html) }
      format.json { redirect_to show_resources_path(rdf_uri: uri_to_load, format: :json)}
    end
  end

  private

    def review_all_statements rdf_uri, status_origin
      statements = []
      _webpages = Webpage.where(rdf_uri: rdf_uri)
      _webpages.each do |webpage|
        webpage.statements.each do |statement|
          statements << statement
        end
      end
      statements.each do |statement|
        if (statement.source.selected && !statement.is_problem?)
          statement.update!(status: "ok", status_origin: status_origin)
        end
      end
    end

    def update_remote_jsonld rdf_uri
      webpages = Webpage.where(rdf_uri: rdf_uri).preload(:website)

      #get all statements for webpage in each language
      condensor_statements = []
      webpages.each do |w|
        w.statements.each do |s|
          condensor_statements << s
        end
      end

      #generate jsonld per language BUT using statements from pages of all languages
      webpages.each do |webpage|
        adr_prefix = "#{webpage.website.graph_name}/resource/"
        jsonld = helpers.build_jsonld condensor_statements, webpage.language, rdf_uri, adr_prefix
        helpers.update_jsonld_on_wringer webpage.url, webpage.website.graph_name, jsonld
      end


    end


end
