# Converts data into a graph using RDF.rb
class GraphsController < ApplicationController
  before_action only: [:webpage_event]

  require 'json/ld'

  # Speed up loading remote JSON-LD context for schema.org
  # def preload_context
  #   begin
  #     ctx = JSON::LD::Context.new().parse('https://schema.org/docs/jsonldcontext.jsonld')
  #     JSON::LD::Context.add_preloaded('http://schema.org/', ctx)
  #     logger.info("Loaded ")
  #   rescue JSON::LD::JsonLdError::LoadingRemoteContextFailed => e
  #     logger.error({ error: "LoadingRemoteContextFailed http://schema.org" })
  #   end
  # end

  # GET /graphs/website/[:seedurl]
  # Queue website to publish to Artsdata 
  def website_queue
    @site = params[:seedurl]
    url_for_messages =  'https://footlight-condenser.herokuapp.com'
    result = ExportToArtsdataJob.perform_later(@site, url_for_messages)
    flash[:info] = "Queued #{@site} for export to Artsdata. Check messages on #{url_for_messages}. Result: #{result}"
    redirect_to root_url
  end

  # Load the website dump and manually go step by step to publish to Artsdata
  def website
    @site = params[:seedurl]
    event_controller = EventsController.new
    @publishable = event_controller.publishable_events(@site)
    @dump = JsonldGenerator.dump_events(@publishable)
  end

  # GET /graphs/webpage/event-artsdata?url=
  def webpage_event_artsdata 
    webpage = Webpage.where(url: CGI.unescape(params[:url]))
    @dump = {}
    if webpage.count.positive?
      @dump = JsonldGenerator.dump_events([webpage.first.rdf_uri])
    end
    respond_to do |format|
      format.jsonld { render inline: @dump, content_type: 'application/ld+json' }
    end
  end

  # GET /graphs/webpage/event?url=
  def webpage_event
    webpage = Webpage.where(url: CGI.unescape(params[:url]))

    if webpage.count.positive?
      resource = Resource.new(webpage.first.rdf_uri)
      main_language = webpage.first.language
      statements = resource.statements.map { |n,v| v}
      main_class = resource.rdfs_class
      problem_statements = helpers.missing_required_properties(statements)
      if problem_statements.blank?
        @google_jsonld = JsonldGenerator.convert(statements, main_language, main_class)
      else
        problems_summary =
          problem_statements
          .map { |s| s[:label] }
          .join(', ')
        @google_jsonld = {
          'message' => "Event needs review in Footlight console. Issues with #{problems_summary}." 
        }.to_json
      end
    else
      @google_jsonld = {
        'message' => 'Webpage fits URL pattern but has no events in the Footlight console.' 
      }.to_json
    end
    logger.info("### Code Snippet Call /graphs/webpage/event?url=#{params[:url]}")
    respond_to do |format|
      format.html {}
      format.jsonld { render inline: @google_jsonld, content_type: 'application/ld+json' }
    end
  end

end
