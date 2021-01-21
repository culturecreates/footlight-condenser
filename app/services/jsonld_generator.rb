# Class to convert data in the Condensor data model to JSON-LD
class JsonldGenerator
  # main method to return converted JSON-LD
  def self.convert(statements, rdf_uri, webpage, main_class = "Event")
    # Build a local graph using condenser statements
    local_graph = build_graph(
      rdf_uri,
      statements,
      { 1 => { 5 => 'http://schema.org/offers' } },
      main_class
    )

    # add additional triples about Places, People, Organizations
    local_graph = add_triples_from_artsdata(local_graph)

    # remove language tags keeping best match
    lang = webpage.first.language
    local_graph = coalesce_language(local_graph, lang)

    # convert to JSON-LD
    graph_json = JSON.parse(local_graph.dump(:jsonld))

    # frame JSON-LD depending on main RDF Class
    graph_json = frame_json(graph_json, main_class)

    # makes changes for Google's flavour of JSON-LD
    graph_json = make_google_jsonld(graph_json)

    # remove IDs that point to artsdata.ca
    delete_ids(graph_json)

    # return as a plain JSON object
    graph_json.to_json
  end

  # Frame JSON-LD to display the desired properties
  def self.frame_json(graph_json, main_class = 'Event')
    frame_json = RDFLoader.load_frame(main_class)
    if frame_json
      graph_json = JSON::LD::API.frame(graph_json, frame_json)
    else
      # There is no JSON-LD Frame for the Class, so just add context instead.
      context = JSON.parse(%({
        "@context": {
          "@vocab": "http://schema.org/"
        }
      }))['@context']
      graph_json = JSON::LD::API.compact(graph_json, context)
    end
    graph_json
  end

  # Add triples from artsdata.ca using URIs of people, places and organizations
  def self.add_triples_from_artsdata(local_graph)
    uris = extract_object_uris(local_graph)
    uris.each do |uri|
      local_graph << describe_uri(uri)
    end
    local_graph
  end

  # coalesce languages to best match before JSON-LF Framing
  def self.coalesce_language(local_graph, lang = "")
    sparql = RDFLoader.load_sparql('coalesce_languages.sparql',["placeholder",lang])
    sse = SPARQL.parse(sparql, update: true)
    local_graph.query(sse)
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
    statements_hash
  end

  def self.make_google_jsonld(jsonld)
    # remove context because Google doesn't like extra types
    puts  jsonld.class 
    jsonld['@context'] = 'https://schema.org/'
    jsonld
  end

  def self.delete_ids(jsonld)
    # remove artsdata @ids to increase Google trust (experiment 2020-10-15)
    jsonld&.delete('@id')
    jsonld['performer']&.delete('@id')
    jsonld['organizer']&.delete('@id')
    jsonld['location']&.delete('@id')
    jsonld['@graph']&.each do |g|
      g&.delete('@id') if g['@id']&.include?('kg.artsdata.ca')
      g['location']&.delete('@id')
      g.dig('location', 'address')&.delete('@id')
      g['performer']&.delete('@id')
      g['performer']&.each { |a| a&.delete('@id') }
      g['organizer']&.delete('@id')
      g['organizer']&.each { |a| a&.delete('@id') }
      g.dig('organizer','address')&.delete('@id')
      g['offers']&.delete('@id')
    end
    jsonld
  end

  # Build a local graph from condenser statements
  def self.build_graph(rdf_uri, statements, nesting_options, main_class = "Event")
    statements_hash = build_statements_hash(statements)
    graph = RDF::Graph.new

    subject = rdf_uri.sub('adr:', 'http://kg.artsdata.ca/resource/')

    # TODO: Make generic - not only Event Class.
    # Interpret the nesting_options
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
        object = if s[:language].present?
                   RDF::Literal(s[:object], language: s[:language])
                 else
                   RDF::Literal(s[:object])
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
  # TODO: Handle language here by selecting best language (coalescing (en, fr, none))?????
  def self.describe_uri(uri)
    query = RDF::Query.new do
      pattern [uri, :p, :o]
    end
    result = query.execute(ArtsdataGraph.graph)
    graph = RDF::Graph.new
    result.each do |s|
      graph << [uri, s.to_h[:p], s.to_h[:o]]

      # add object type if object is a URI 
      # Example: set schema:sameAs object urls to be type schema:URL
      if s.to_h[:o].uri?
        query3 = RDF::Query.new do
          pattern [s.to_h[:o], RDF.type, :c]
        end
        result3 = query3.execute(ArtsdataGraph.graph)
        result3.each { |st| graph << [s.to_h[:o], RDF.type, st.to_h[:c]] }
      end

      # add blank nodes one level deep
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
