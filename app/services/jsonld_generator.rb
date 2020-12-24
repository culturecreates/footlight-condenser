# Class to convert data in the Condensor data model to JSON-LD
class JsonldGenerator
  # main method to return converted JSON-LD
  def self.convert(statements, rdf_uri, webpage, main_class = "Event")
    local_graph = build_graph(
      rdf_uri,
      statements,
      { 1 => { 5 => 'http://schema.org/offers' } },
      main_class
    )

    local_graph = add_triples_from_artsdata(local_graph)

    # convert to JSON-LD
    graph_json = JSON.parse(local_graph.dump(:jsonld))
    
    # frame JSON-LD depending on main RDF Class
    lang = webpage.first.language
    frame_json = FrameLoader.load(main_class, lang)
    if frame_json
      graph_json = JSON::LD::API.frame(graph_json, frame_json)
      graph_json = make_google_jsonld(graph_json)
      delete_ids(graph_json)
    else
      context = JSON.parse(%({
        "@context": {
          "@vocab": "http://schema.org/"
        }
      }))['@context']
      graph_json = JSON::LD::API.compact(graph_json, context)
      delete_ids(graph_json)
    end
   
   
    graph_json.to_json
  end

  # Add triples from artsdata.ca using URIs of people, places and organizations
  def self.add_triples_from_artsdata(local_graph)
    uris = extract_object_uris(local_graph)
    uris.each do |uri|
      local_graph << describe_uri(uri)
    end
    local_graph
  end

  # create a HASH of statements
  def self.build_statements_hash(statements)
    statements_hash = statements.map do |s|
      { status: s.status,
        rdfs_class: s.source.property.rdfs_class_id,
        rdfs_class_name: s.source.property.rdfs_class.name,
        predicate: s.source.property.uri,
        object: s.cache,
        language: s.source.language,
        value_datatype: s.source.property.value_datatype,
        label: s.source.property.label }
    end
    # map statements that have a datatype xsd:anyURI to a list of URIs
    statements_hash.map { |s|  s[:object] = JsonUriWrapper.extract_uris_from_cache(s[:object]) if s[:value_datatype] == "xsd:anyURI" }
    # remove any blank statements
    statements_hash.select! { |s| s[:object].present? && s[:object] != '[]' }
    return statements_hash
  end

  def self.make_google_jsonld(jsonld)
    return unless jsonld['@graph']

    # remove context because Google doesn't like extra types
    jsonld['@graph'][0].merge('@context' => 'https://schema.org/')
  end

  def self.delete_ids(jsonld)
    # remove artsdata @ids to increase Google trust (experiment 2020-10-15)
    jsonld.delete('@id')
    jsonld["performer"].delete('@id') if  jsonld["performer"]
    jsonld["organizer"].delete('@id') if  jsonld["organizer"]
    jsonld["location"].delete('@id') if  jsonld["location"]
    if jsonld["@graph"]
      jsonld["@graph"].each do |g|
        g.delete('@id') if g['@id'].include?('kg.artsdata.ca')
      end
    end
  end

  # Build a local graph from condenser statements
  def self.build_graph(rdf_uri, statements, nesting_options, main_class = "Event")
    statements_hash = build_statements_hash(statements)
    
    graph = RDF::Graph.new

    subject = rdf_uri.sub('adr:', 'http://kg.artsdata.ca/resource/')

    # TODO: Make generic - not only Event Class.
    # Interpret the nesting_options
    pp nesting_options
    # create main Class and blank nodes for each nested class
    # and set subject first thing inside loop.
    
    main_class_uri = "http://schema.org/#{main_class}"
    graph << [RDF::URI(subject), RDF.type, RDF::URI(main_class_uri)]
    statements_hash.each do |s|
      next if s[:status] == 'initial' || s[:status] == 'problem'

      ## TEMPORARY PATCH START #########
      if s[:rdfs_class] == 5
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/offers'), :bn]
        graph << [:bn, RDF.type, RDF::URI('http://schema.org/Offer')]
        s[:object].make_into_array.each do |url|
          puts "Offer: adding #{url}"
          graph << [:bn, RDF::URI(s[:predicate]), RDF::Literal(url)]
        end
      elsif s[:rdfs_class] == 41
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/eventStatus'), :bn]
        graph << [:bn,  RDF.type, RDF::URI('http://schema.org/EventStatusType')]
        graph << [:bn, RDF::URI(s[:predicate]), RDF::URI()]
      elsif s[:rdfs_class_name] == "VirtualLocation"
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/location'), :bn3]
        graph << [:bn3, RDF.type, RDF::URI('http://schema.org/VirtualLocation')]
        graph << [:bn3, RDF::URI(s[:predicate]), s[:object]]
      elsif s[:rdfs_class_name] == "PostalAddress"
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/address'), :bn4 ]
        graph << [ :bn4 , RDF.type, RDF::URI('http://schema.org/PostalAddress')]
        graph << [ :bn4 , RDF::URI(s[:predicate]), s[:object]]
      ## TEMPORARY PATCH  END #########

      elsif  s[:value_datatype] == 'xsd:anyURI'
        s[:object].each do |uri|
          graph << [RDF::URI(subject), RDF::URI(s[:predicate]), RDF::URI(uri)]
          # add describe URI to graph
        end
      elsif  s[:value_datatype] == 'xsd:dateTime'
        s[:object].make_into_array.each do |date_time|
          if RDF::Literal::DateTime.new(date_time).valid?
            graph << [RDF::URI(subject), RDF::URI(s[:predicate]), RDF::Literal::DateTime.new(date_time)] 
          elsif RDF::Literal::Date.new(date_time).valid?
            graph << [RDF::URI(subject), RDF::URI(s[:predicate]), RDF::Literal(date_time)] 
          end
        end
      else
        if s[:language].present?
          object = RDF::Literal(s[:object], language: s[:language])
        else
          object = RDF::Literal(s[:object])
        end
        graph << [RDF::URI(subject), RDF::URI(s[:predicate]), object]
      end
    end
    graph
  end

  # Return a list of URIs to be nested inside the JSON-LD
  def self.extract_object_uris(graph)
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
