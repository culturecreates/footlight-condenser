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
                  statements: {}}

    webpages = Webpage.where(rdf_uri: params[:rdf_uri])
    @resource[:rdfs_class] = webpages.first.rdfs_class.name if !webpages.empty?
   @resource[:seedurl] = webpages.first.website.seedurl if !webpages.empty?

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
      statement.update!(status: "ok", status_origin: params[:event][:status_origin]) if (statement.source.selected && !statement.is_problem?)
    end

    uri_to_load = params[:rdf_uri]
    if params[:review_next] == "true"
      #get next rdf_uri
      uris_to_review = Statement.joins({webpage: :website},:source, {webpage: :rdfs_class}).where(webpages:{websites: {seedurl: params[:seedurl]}, rdfs_classes: {name: "Event"}}).where(sources: {selected: true}).where(status: "initial").pluck(:rdf_uri).uniq
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
