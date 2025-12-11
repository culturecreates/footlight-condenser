# =============================================================================
# NOTE ON RESOURCE VS ACTIVE RECORD USAGE
# -----------------------------------------------------------------------------
# The Resource class is a "Plain Old Ruby Object" (PORO) wrapper that represents
# a logical entity composed of one or more Webpage ActiveRecord objects.
#
# DO NOT use ActiveRecord finder methods (`find_by`, `.create!`, `.where`, etc.)
# on Resource. It is not a database-backed model!
#
# Instead:
#   - Check for existence using the underlying Webpage model:
#       webpages = Webpage.where(rdf_uri: params[:rdf_uri])
#       if webpages.blank? ... head :not_found ...
#   - Instantiate a Resource object using:
#       resource = Resource.new(params[:rdf_uri])
#
# You MAY use ActiveRecord methods freely on Webpage, Statement, Property, etc.
# =============================================================================
class ResourcesController < ApplicationController
  skip_before_action :verify_authenticity_token, :authenticate

  # === GET /recon
  # Returns matching statements for the given query and type.
  def recon
    # Validate required params
    unless params[:query].present? && params[:type].present?
      return render json: { error: "Missing required params" }, status: :bad_request
    end

    # Find matching statements
    hits = Statement.joins(source: :property)
                    .where(status: ['ok', 'updated'])
                    .where("lower(cache) LIKE ?", "%#{params[:query].downcase}%")
                    .where(sources: { selected: true, properties: { label: ['Name', 'alternateName'], rdfs_class: RdfsClass.where(name: params[:type]) } })
                    .distinct
                    .pluck(:cache, :webpage_id)

    # Build response
    @response = { result: hits.map { |hit|
      {
        name: hit[0],
        description: Statement.joins(source: :property)
                              .where(webpage_id: hit[1], sources: { properties: { label: 'Disambiguating Description' } })
                              .pluck(:cache),
        id: Webpage.find_by(id: hit[1])&.rdf_uri&.gsub("footlight:", "")
      }
    }}
    render json: @response, callback: params['callback']
  end

  # === GET /resource?uri={uri}
  # Shows a single resource given a URI param, or returns 400 if missing.
  def uri
    unless params[:uri].present?
      return render json: { error: "Missing uri param" }, status: :bad_request
    end
    webpages = Webpage.where(rdf_uri: params[:uri])
    if webpages.blank?
      return head :not_found
    end
    @resource = Resource.new(params[:uri])
    @statement_keys = @resource.statements.keys.sort
    render 'show'
  end

  # === GET /websites/:seedurl/resources
  # Returns grouped resource URIs for a seedurl (website)
  def index
    unless params[:seedurl].present?
      return render json: { error: "Missing seedurl param" }, status: :bad_request
    end
    @resources = {}
    @resources["event"]         = helpers.get_uris(params[:seedurl], "Event")
    @resources["place"]         = helpers.get_uris(params[:seedurl], "Place")
    @resources["organization"]  = helpers.get_uris(params[:seedurl], "Organization")
    @resources["person"]        = helpers.get_uris(params[:seedurl], "Person")
    @resources["event_type"]    = helpers.get_uris(params[:seedurl], "EventType")
    @resources["resource_list"] = helpers.get_uris(params[:seedurl], "ResourceList")
    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @resources }
    end
  end

  # === Utility for getting non-Event entities by seedurl (internal use)
  def other_entities(seedurl)
    rdfs_classes = RdfsClass.all.reject { |c| c.name == 'Event' }
    statements =
      Statement
      .includes({ source: [:property, :website] }, :webpage)
      .where(sources: { websites: { seedurl: seedurl }, webpages: { rdfs_class_id: rdfs_classes } })
      .where(selected_individual: true)
    statements.pluck(:rdf_uri).uniq
  end

  # === GET /resources/:rdf_uri
  # Shows a resource and its statements. Returns 404 if not found.
  def show
    @resource = resource_for_param!
    return unless @resource
    @statement_keys = @resource.statements.keys.sort
    # Renders show.html.erb or show.json
  end

  # === POST /resources
  # Creates a new resource with given params. Returns 422 if params invalid.
  def create_resource
    unless params[:rdfs_class].present? && params[:seedurl].present? && params[:statements].present?
      return render json: { error: "Missing one or more required params" }, status: :unprocessable_entity
    end
    minted_uri = "footlight:#{SecureRandom.uuid}"
    @resource = Resource.new(minted_uri)
    @resource.rdfs_class = params[:rdfs_class]
    @resource.seedurl    = params[:seedurl]
    if @resource.save(params[:statements])
      render :show, status: :created
    else
      render json: @resource.errors, status: :unprocessable_entity
    end
  end

  # === GET /resources/:rdf_uri/webpage_urls
  # Returns webpage URLs for a resource, or 404 if resource not found
  def webpage_urls
    webpages = webpages_for_param!
    return unless webpages
    @urls = webpages
    render :webpage_urls, formats: :json
  end

  # === DELETE /resources/:rdf_uri
  # Destroys all webpages for this rdf_uri. Returns 404 if not found.
  def destroy
    webpages = webpages_for_param!
    return unless webpages
    webpages.each(&:destroy)
    respond_to do |format|
      format.html { redirect_to "/websites/events", notice: 'Resource was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  # === DELETE /resources/delete_uri.json?uri=
  # Destroys webpages for a given ?uri= param (used for certain API flows)
  def delete_uri
    unless params[:uri].present?
      return render json: { error: "Missing uri param" }, status: :bad_request
    end
    webpages = Webpage.where(rdf_uri: params[:uri])
    webpages.each(&:destroy)
    respond_to do |format|
      format.html { redirect_to "/websites/events", notice: 'Resource was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  # === PATCH /resources/:rdf_uri/archive
  # Sets archive_date for all webpages of a resource, or returns 404 if not found.
  def archive
    webpages = webpages_for_param!
    return unless webpages
    review_all_statements params[:rdf_uri], params[:event][:status_origin]        # Does this exist?
    webpages.each { |webpage| webpage.update(archive_date: Time.zone.now - 1.day) }
    respond_to do |format|
      format.html { redirect_to "/websites/events", notice: 'Event was successfully archived.' }
      format.json { head :no_content }
    end
  end

  # === PATCH /resources/:rdf_uri/reviewed_all
  # Marks all resource statements as reviewed (except flagged). Returns 404 if not found.
  def reviewed_all
    @resource = resource_for_param!
    return unless @resource

    @resource.review_all_resource_except_flagged(params[:event][:status_origin])

    uri_to_load = params[:rdf_uri]
    if params[:review_next] == "true"
      uris_to_review = Statement.joins({webpage: :website}, :source, {webpage: :rdfs_class})
        .where(webpages: {websites: {seedurl: params[:seedurl]}, rdfs_classes: {name: "Event"}})
        .where(sources: {selected: true})
        .where(status: "initial")
        .or(
          Statement.joins({webpage: :website}, :source, {webpage: :rdfs_class})
            .where(webpages: {websites: {seedurl: params[:seedurl]}, rdfs_classes: {name: "Event"}})
            .where(sources: {selected: true})
            .where(status: "updated")
        )
        .order(:created_at)
        .pluck(:rdf_uri)
        .uniq
      uri_to_load = uris_to_review.first if uris_to_review.present?
    end
    respond_to do |format|
      format.html { redirect_to show_resources_path(rdf_uri: uri_to_load, format: :html) }
      format.json { redirect_to show_resources_path(rdf_uri: uri_to_load, format: :json)}
    end
  end

  private

  # === Helper: Find Webpages for params[:rdf_uri], else 404
  def webpages_for_param!
    @webpages = Webpage.where(rdf_uri: params[:rdf_uri])
    if @webpages.empty?
      head :not_found
      return nil
    end
    @webpages
  end

  # === Helper: Find Resource for params[:rdf_uri], else 404
def resource_for_param!
  webpages = Webpage.where(rdf_uri: params[:rdf_uri])
  if webpages.blank?
    head :not_found
    return nil
  end
  Resource.new(params[:rdf_uri])
end
end
