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
  def website
    @site = params[:seedurl] 
    event_controller = EventsController.new
    @publishable = event_controller.publishable_events(@site)
    @dump = JsonldGenerator.dump_events(@publishable)
  end

  # GET /graphs/webpage/event?url=
  def webpage_event
    webpage = Webpage.where(url: CGI.unescape(params[:url]))

    # Get all the webpages related to this webpage's resource URI
    if webpage.count.positive?
      rdf_uri = webpage.first.rdf_uri
      webpages = Webpage.where(rdf_uri: rdf_uri)
      main_class = webpage.first.rdfs_class.name
      main_language = webpage.first.language
    end
    if webpages.present?

      statements = selected_statements(webpages)

      problem_statements = helpers.missing_required_properties(statements)

      if problem_statements.blank?

        @google_jsonld = JsonldGenerator.convert(statements, main_language, main_class)
      else
        problems_summary =
          problem_statements
          .map { |s| s.source.property.label }
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

  private 

  # get statements linked to the webpage that have selected sources.
  def selected_statements(webpages)
    statements =
      Statement
      .joins({ source: :property })
      .where(webpage_id: webpages, sources: { selected: true })
  end
end
