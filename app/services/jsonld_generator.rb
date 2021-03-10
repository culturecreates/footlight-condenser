# Class to convert data in the Condensor data model to JSON-LD
class JsonldGenerator
  # main method to dump all statements into a graph to push to artsdata
  def self.dump_events(events) # list of event uris
    graphs = RDF::Graph.new
    events.each do |uri|
      statements = load_uri_statements(uri)
      graph = build_graph(statements, {})
      graph = add_triples_from_artsdata(graph)
      graphs << graph
    end
    graphs.dump(:jsonld)
  end

  # Load all ActiveRecord Statements that are selected 'true'
  def self.load_uri_statements(rdf_uri)
    # A uri may span statements from an english and french webpage
    webpages = Webpage.where(rdf_uri: rdf_uri)
    statements = Statement.joins({ source: :property }).where(webpage_id: webpages, sources: { selected: true })
    statements
  end

  # main method to return converted JSON-LD for a webpage with code snippet
  def self.convert(statements, main_language, main_class = "Event")
    # Build a local graph using condenser statements
    local_graph = build_graph(statements,{ 1 => { 5 => 'http://schema.org/offers' } })

    # add additional triples about Places, People, Organizations
    local_graph = add_triples_from_artsdata(local_graph)

    # remove language tags keeping best match
    local_graph = coalesce_language(local_graph, main_language)

    # convert to JSON-LD
    graph_json = JSON.parse(local_graph.dump(:jsonld))

    # frame JSON-LD depending on main RDF Class
    # select a subset of properties for SDTT
    # move xsd:dateTime to context since Google SDTT complains, 
    # then remove from context in next step so it is completely gone
    graph_json = frame_json(graph_json, main_class)

    # makes changes for Google's flavour of JSON-LD
    # remove xsd:dateTime from context since Google SDTT complains 
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
      additional_graph = describe_uri(uri)
      # TODO: fetch remote data if additional_graph.count == 0
      local_graph << additional_graph
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
        webpage_class_name: s.webpage.rdfs_class.name,
        subject: s.webpage.rdf_uri,
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
    # remove context because Google doesn't like extra data types like xsd:dateTime
    jsonld['@context'] = 'https://schema.org/'
    jsonld
  end

  def self.delete_ids(jsonld)
    # remove artsdata @ids to increase Google trust (experiment 2020-10-15)
    # TODO: Make this recursive
    jsonld&.delete('@id')
    # jsonld['performer']&.delete('@id')
    # jsonld['organizer']&.delete('@id')
    # jsonld['location']&.delete('@id')
    jsonld['@graph']&.each do |g|
      g&.delete('@id') if g['@id']&.include?('kg.artsdata.ca')
      # g['location']&.delete('@id')
      # g['performer']&.delete('@id')
      # g['performer']&.each { |a| a&.delete('@id') }
      # g['organizer']&.delete('@id')
      # g['organizer']&.each { |a| a&.delete('@id') }
      g['offers']&.delete('@id')
    end
    jsonld
  end

  # Returns an RDF graph from condenser statements
  def self.build_graph(statements, nesting_options = {})
    statements_hash = build_statements_hash(statements)
    graph = RDF::Graph.new

    statements_hash.each do |s|
      next if s[:status] == 'initial' || s[:status] == 'problem'

      main_class_uri = "http://schema.org/#{s[:webpage_class_name]}"
      subject = s[:subject].sub('adr:', 'http://kg.artsdata.ca/resource/')
      graph << [RDF::URI(subject), RDF.type, RDF::URI(main_class_uri)]


      ## TEMPORARY PATCH START #########
      # TODO: Make generic
      puts "nesting_options unused: #{nesting_options}"
      # Interpret the nesting_options to remove this patch

      if s[:rdfs_class_name] == 'Offer'
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/offers'), build_uri(subject,'Offer')]
        graph << [build_uri(subject,'Offer'), RDF.type, RDF::URI('http://schema.org/Offer')]
        s[:object].make_into_array.each do |url|
          graph << [build_uri(subject,'Offer'), RDF::URI(s[:predicate]), RDF::Literal(url)]
        end
      elsif s[:rdfs_class_name] == 'EventStatus'
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/eventStatus'), build_uri(subject,'EventStatus')]
        graph << [build_uri(subject, 'EventStatus'), RDF.type, RDF::URI('http://schema.org/EventStatusType')]
        graph << [build_uri(subject, 'EventStatus'), RDF::URI(s[:predicate]), RDF::URI()]
      elsif s[:rdfs_class_name] == 'VirtualLocation'
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/location'), build_uri(subject,'VirtualLocation')]
        graph << [build_uri(subject, 'VirtualLocation'), RDF.type, RDF::URI('http://schema.org/VirtualLocation')]
        graph << [build_uri(subject, 'VirtualLocation'), RDF::URI(s[:predicate]), s[:object]]
      elsif s[:rdfs_class_name] == 'PostalAddress'
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/address'), build_uri(subject,'PostalAddress')]
        graph << [build_uri(subject, 'PostalAddress'), RDF.type, RDF::URI('http://schema.org/PostalAddress')]
        graph << [build_uri(subject, 'PostalAddress'), RDF::URI(s[:predicate]), s[:object]]
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

  # Build a URI using subject URI and appending 'str'
  def self.build_uri(subject, str)
    if subject.include?('#')
      RDF::URI("#{subject}-#{str}")
    else
      RDF::URI("#{subject}##{str}")
    end
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

      # If object is a URI then add one level deep to capture location address etc.
      if s.to_h[:o].uri?
        query3 = RDF::Query.new do
          pattern [s.to_h[:o], :b, :c]
        end
        result3 = query3.execute(ArtsdataGraph.graph)
        result3.each { |st| graph << [s.to_h[:o], st.to_h[:b], st.to_h[:c]] }
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
