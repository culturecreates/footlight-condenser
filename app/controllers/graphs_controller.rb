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

  # GET /graphs/webpage/event?url=
  def webpage_event
    webpage = Webpage.where(url: CGI.unescape(params[:url]))

    # Get all the webpages related to this webpage's resource URI
    if webpage.count.positive?
      rdf_uri = webpage.first.rdf_uri
      webpages = Webpage.where(rdf_uri: rdf_uri)
    end
    if webpages.present?

      # get statements linked to the webpage that have selected sources.
      statements =
        Statement
        .joins({ source: :property })
        .where(webpage_id: webpages, sources: { selected: true })

      problem_statements = helpers.missing_required_properties(statements)

      if problem_statements.blank?

        @google_jsonld = JsonldGenerator.convert(statements, rdf_uri, webpage, webpage.first.rdfs_class.name )
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
end

