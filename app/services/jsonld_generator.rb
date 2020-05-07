# Class to convert data in the Condensor data model to JSON-LD
class JsonldGenerator
  extend ResourcesHelper

  # main method to return converted JSON-LD
  def self.convert(statements, rdf_uri, webpage)
    local_graph = build_graph(
      rdf_uri,
      statements,
      { 1 => { 5 => 'http://schema.org/offers' } }
    )

    local_graph = add_triples_from_artsdata(local_graph)

    # convert to JSON-LD
    json_graph = JSON.parse(local_graph.dump(:jsonld))

    # frame JSON-LD
    jsonld = JSON::LD::API.frame(json_graph, FrameLoader.event(webpage.first.language))

    # remove context because Google doesn't like extra types
    google_jsonld = make_google_jsonld(jsonld)
  end

  # Add triples from artsdata.ca using URIs of people, places and organizations
  def self.add_triples_from_artsdata(local_graph)
    uris = extract_object_uris(local_graph)
    uris.each do |uri|
      local_graph << describe_uri(uri)
    end
    local_graph
  end

  # create a HASH for statements
  def self.build_statements_hash statements
    statements_hash = statements.map do |s|
      { status: s.status,
        rdfs_class: s.source.property.rdfs_class_id,
        predicate: s.source.property.uri,
        object: s.cache,
        language: s.source.language,
        value_datatype: s.source.property.value_datatype,
        label: s.source.property.label }
    end
    # map statements that have a datatype xsd:anyURI to a list of URIs
    statements_hash.map { |s|  s[:object] = extract_uri(s[:object]) if s[:value_datatype] == "xsd:anyURI" }
    # remove any blank statements
    statements_hash.select! { |s| s[:object].present? && s[:object] != '[]'}
  end

  def self.extract_uri(cache)
    cache_obj = build_json_from_anyURI(cache)
    cache_obj.pluck(:links).flatten.pluck(:uri)
  end

  def self.make_google_jsonld jsonld
    jsonld["@graph"][0].merge("@context" => "http://schema.org").to_json
  end

  # Build a local graph from condenser statements
  def self.build_graph(rdf_uri, statements, nesting_options)
    statements_hash = build_statements_hash(statements)
    graph = RDF::Graph.new

    subject = rdf_uri.sub('adr:', 'http://kg.artsdata.ca/resource/')

    # TODO: Make generic - not only Event Class. 
    # Interpret the nesting_options, 
    # create main Class and blank nodes for each nested class 
    # and set subject first thing inside loop.
    graph << [RDF::URI(subject), RDF.type, RDF::URI('http://schema.org/Event')]
    statements_hash.each do |s|

        ## TEMPORARY PATCH START #########
        if s[:rdfs_class] == 5 
            graph << [RDF::URI(subject), RDF::URI("http://schema.org/offers"), :bn ]
            graph << [ :bn,  RDF.type,  RDF::URI("http://schema.org/Offer")]
            s[:object].make_into_array.each do |url|
              puts "Offer: adding #{url}" 
              graph << [ :bn, RDF::URI(s[:predicate]), RDF::Literal(url)]
            end
            
        elsif s[:rdfs_class] == 41 
            graph << [RDF::URI(subject), RDF::URI("http://schema.org/eventStatus"), :bn ]
            graph << [ :bn,  RDF.type,  RDF::URI("http://schema.org/EventStatusType")]
            graph << [ :bn, RDF::URI(s[:predicate]), RDF::URI()]
        ## TEMPORARY PATCH  END #########

        elsif  s[:value_datatype] == "xsd:anyURI"
            s[:object].each do |uri|
                graph << [RDF::URI(subject), RDF::URI(s[:predicate]), RDF::URI(uri)] 
                #add describe URI to graph  
            end
        elsif  s[:value_datatype] == 'xsd:dateTime'
          s[:object].make_into_array.each do |date_time|
            if RDF::Literal::DateTime.new(date_time).valid?
              graph << [RDF::URI(subject), RDF::URI(s[:predicate]), RDF::Literal::DateTime.new(date_time)] 
            end
          end

        else
            if s[:language].present? 
                object = RDF::Literal(s[:object], language: s[:language])
                puts "Non-offer lang object #{object}"
            else
                object = RDF::Literal(s[:object])
                puts "Non-offer object #{object}"
            end
            graph << [RDF::URI(subject), RDF::URI(s[:predicate]), object] 
        end
    end
    graph
  end

  def self.extract_object_uris graph
    query = RDF::Query.new do
      pattern [:s, :p, :object]
    end
    solutions = query.execute(graph)
    solutions.filter! { |solution| solution.object.uri? }

    uri_list = []
    solutions.each { |s| uri_list << s.to_h[:object] }
    uri_list
  end

  # Get triples about a URI from Artsdata.ca
  def self.describe_uri(uri)
    query = RDF::Query.new do
      pattern [uri, :p, :o]
    end
    result = query.execute(ArtsdataGraph.graph)
    graph = RDF::Graph.new
    result.each do |s|
      graph << [uri, s.to_h[:p], s.to_h[:o]]
      if s.to_h[:o].node?
        # Add blank nodes in object position to expand describe for location which contains a blank node for address.
        query2 = RDF::Query.new do
          pattern [s.to_h[:o], :bnp, :bno]
        end
        result2 = query2.execute(ArtsdataGraph.graph)
        result2.each { |bns| graph << [s.to_h[:o], bns.to_h[:bnp], bns.to_h[:bno]] }
      end
    end
    graph
  end
end
