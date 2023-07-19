# Class to convert data in the Condensor data model to JSON-LD
class JsonldGenerator
  extend ResourcesHelper # for method adjust_labels_for_api
  
  # main method to dump all statements into a graph to push to artsdata
  def self.dump_events(events) # list of event uris
    graphs = RDF::Graph.new
    events.each do |uri|
      statements = load_uri_statements(uri)
      statements_hash = statements.map{ |stat| adjust_labels_for_api(stat, subject: stat.webpage.rdf_uri, webpage_class_name: stat.webpage.rdfs_class.name  ) }
      graph = build_graph(statements_hash, {for_artsdata: true})
      graph = make_contact_series(graph, uri)
      graph = make_event_series(graph, uri)
      graph = add_triples_from_footlight(graph)
      graphs << graph
    end
    graphs = remove_annotations(graphs)
    graphs.dump(:jsonld)
  end

  # Load all ActiveRecord Statements for a URI that are selected_individual 'true'
  def self.load_uri_statements(rdf_uri)
    webpages = Webpage.where(rdf_uri: rdf_uri) # A uri may span statements from an english and french webpage
    statements = Statement.where(webpage_id: webpages, selected_individual: true)
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

    # makes changes for Google's flavour of RDF
    local_graph = make_google_graph(local_graph)

    # convert to JSON-LD
    graph_json = JSON.parse(local_graph.dump(:jsonld))

    # frame JSON-LD depending on main RDF Class
    # select a subset of properties for SDTT
    graph_json = frame_json(graph_json, main_class)

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

  # Add triples from artsdata.ca AND Footlight database using URIs of people, places and organizations
  def self.add_triples_from_artsdata(local_graph)
    uris = extract_object_uris(local_graph)
    uris.each do |uri|
      additional_graph = describe_uri(uri)
      # TODO: fetch remote data from Wikidata if additional_graph.count == 0
      local_graph << additional_graph
    end
    local_graph
  end

  # Add triples ONLY from Footlight database (not Artsdata) using URIs of people, places and organizations
  def self.add_triples_from_footlight(local_graph)

    ## Refresh local entities (People, Places, Organizations) entered manually into Footlight
    # ArtsdataGraph.graph << LocalGraphGenerator.graph_all

    uris = extract_object_uris(local_graph)
    uris.each do |uri|
      if !uri.value.include?("http://kg.artsdata.ca/resource/K")
        additional_graph = describe_uri(uri)
        local_graph << additional_graph
      end
    end
    local_graph
  end


  # coalesce languages to best match before JSON-LD Framing
  def self.coalesce_language(local_graph, lang = '')
    sparql = RDFLoader.load_sparql('coalesce_languages.sparql', ['placeholder', lang])
    sse = SPARQL.parse(sparql, update: true)
    local_graph.query(sse)
    local_graph
  end


  # make Google SDTT pass by removing data types like xsd:dateTime and xsd:date
  def self.make_google_graph(local_graph)
    sparql = RDFLoader.load_sparql('remove_date_datatypes.sparql')
    sse = SPARQL.parse(sparql, update: true)
    local_graph.query(sse)
    local_graph
  end

  def self.remove_annotations(local_graph)
    sparql = RDFLoader.load_sparql('remove_annotations.sparql')
    sse = SPARQL.parse(sparql, update: true)
    local_graph.query(sse)
    local_graph
  end

  def self.count_quoted_triples(local_graph, prop)
    sparql = SPARQL.parse("SELECT * WHERE { <<?s <http://schema.org/#{prop}> ?o>> <http://schema.org/position> ?pos }")
    result = local_graph.query(sparql)
    result.count
  end

  # resolve prefix if present
  def self.full_uri(uri)
    uri.gsub("adr:", "http://kg.artsdata.ca/resource/").gsub("footlight:", "http://kg.footlight.io/resource/")
  end

  # convert a list of ContactPoint names and phones into seperate ContactPoints
  def self.make_contact_series(local_graph, uri)
    filename = "make_contact_series.sparql"
    sparql = RDFLoader.load_sparql(filename,["http://kg.artsdata.ca/resource/spec-qc-ca_broue", full_uri(uri)])
    begin
      sse = SPARQL.parse(sparql, update: true)
      local_graph.query(sse)
    rescue => exception
      Rails.logger.error "ERROR: #{exception}"
    end
    local_graph
  end

  # convert a list of startDates into subEvents
  def self.make_event_series(local_graph, uri)
    number_of_start_dates = count_quoted_triples(local_graph,'startDate')

    return local_graph unless number_of_start_dates > 1

    number_of_locations = count_quoted_triples(local_graph,'location')
    number_of_end_dates = count_quoted_triples(local_graph,'endDate')

    ##################################
    # Log bad situations
    ##################################
    if number_of_locations > 1 && number_of_locations != number_of_start_dates
      Rails.logger.error "ERROR: converting #{full_uri(uri)} to EventSeries. Unequal number_of_locations:#{number_of_locations} and number_of_start_dates:#{number_of_start_dates}."
    end
    if number_of_end_dates > 0 && number_of_end_dates != number_of_start_dates
      Rails.logger.info "INFO: warning converting #{full_uri(uri)} to EventSeries. Unequal number_of_end_dates:#{number_of_end_dates} and number_of_start_dates:#{number_of_start_dates}."
    end    

    filename =  if number_of_locations > 1 && number_of_start_dates == number_of_locations && number_of_start_dates == number_of_end_dates
                  'event_series_locations.sparql'
                elsif  number_of_locations > 1  && number_of_start_dates != number_of_end_dates && number_of_start_dates == number_of_locations
                  'event_series_locations_only_start_dates.sparql'
                elsif  number_of_locations < 2 && number_of_end_dates != number_of_start_dates
                  'event_series_dates_only_start_dates.sparql'
                elsif  number_of_locations < 2 && number_of_end_dates == number_of_start_dates  
                  'event_series_dates.sparql'
                end
    
    
    # TODO: Better handling of error 
    return RDF::Graph.new unless filename

    sparql = RDFLoader.load_sparql(filename,["http://kg.artsdata.ca/resource/spec-qc-ca_broue", full_uri(uri)])

    begin
      sse = SPARQL.parse(sparql, update: true)
      local_graph.query(sse)
    rescue => exception
      Rails.logger.error "ERROR: #{exception}"
    end
    local_graph
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
      g&.delete('@id') if g['@id']&.include?('kg.footlight.io')
      # g['location']&.delete('@id')
      # g['performer']&.delete('@id')
      # g['performer']&.each { |a| a&.delete('@id') }
      # g['organizer']&.delete('@id')
      # g['organizer']&.each { |a| a&.delete('@id') }
      g['offers']&.delete('@id')
    end
    jsonld
  end

  # Returns an RDF graph from condenser statements hash
  def self.build_graph(statements, nesting_options = {})    
    # map statements that have a datatype xsd:anyURI to a list of URIs
    statements.map { |s|  s[:value] = JsonUriWrapper.extract_uris_from_cache(s[:value]) if s[:datatype] == "xsd:anyURI" }
    # remove any blank statements
    statements.select! { |s| s[:value].present? && s[:value] != '[]' }
    
    graph = RDF::Graph.new

    statements.each do |s|
      next if s['status'] == 'initial' || s['status'] == 'problem'

      next if s[:predicate].empty? 

      main_class_uri = "http://schema.org/#{s[:webpage_class_name]}"
      subject = full_uri(s[:subject])
      
      graph << [RDF::URI(subject), RDF.type, RDF::URI(main_class_uri)]

      # Add data changed Observation
      if s['cache_changed']
        observation_uri = build_uri(subject,"Observation_#{s[:label]}".gsub(" ","-"))
        graph << [observation_uri, RDF.type, RDF::URI('http://schema.org/Observation')]
        graph << [observation_uri, RDF::URI('http://schema.org/observedNode'), RDF::URI(subject)]
        graph << [observation_uri, RDF::URI('http://schema.org/measuredProperty'), RDF::URI(s[:predicate])]
        graph << [observation_uri, RDF::URI('http://schema.org/observationDate'), RDF::Literal::DateTime.new(s["cache_changed"])]
        graph << [observation_uri, RDF::URI('http://schema.org/name'), RDF::Literal("#{s[:label]} property changed")]
      end

      ## TEMPORARY PATCH START #########
      # TODO: Make generic, maybe use frames to explicit the data strucutre of nested entites?
      # puts "nesting_options unused: #{nesting_options}"
      # Interpret the nesting_options to remove this patch

      if s[:rdfs_class_name] == 'Offer'
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/offers'), build_uri(subject,'Offer')]
        graph << [build_uri(subject,'Offer'), RDF.type, RDF::URI('http://schema.org/Offer')]
        s[:value].make_into_array.each_with_index do |str, index|
          statement = RDF::Statement(build_uri(subject,'Offer'), RDF::URI(s[:predicate]), RDF::Literal(str))
          graph << statement
          graph << [statement,  RDF::URI('http://schema.org/position'), index] if nesting_options[:for_artsdata]
        end
      elsif s[:rdfs_class_name] == 'VirtualLocation'
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/location'), build_uri(subject,'VirtualLocation')]
        graph << [build_uri(subject, 'VirtualLocation'), RDF.type, RDF::URI('http://schema.org/VirtualLocation')]
        graph << [build_uri(subject, 'VirtualLocation'), RDF::URI(s[:predicate]), s[:value]]
      elsif s[:rdfs_class_name] == 'PostalAddress'
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/address'), build_uri(subject,'PostalAddress')]
        graph << [build_uri(subject, 'PostalAddress'), RDF.type, RDF::URI('http://schema.org/PostalAddress')]
        object = if s[:language].present?
          RDF::Literal(s[:value], language: s[:language])
        else
          RDF::Literal(s[:value])
        end
        graph << [build_uri(subject, 'PostalAddress'), RDF::URI(s[:predicate]), object]
      elsif s[:rdfs_class_name] == 'WebPage'
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/mainEntityOfPage'), build_uri(s[:value],'WebPage')]
        graph << [build_uri(s[:value], 'WebPage'), RDF.type, RDF::URI('http://schema.org/WebPage')]
        graph << [build_uri(s[:value], 'WebPage'), RDF::URI('http://schema.org/inLanguage'), s[:language]] if s[:language].present?
        graph << [build_uri(s[:value], 'WebPage'), RDF::URI('http://schema.org/lastReviewed'), RDF::Literal::DateTime.new(s["cache_refreshed"])] if s["cache_refreshed"].present?
        graph << [build_uri(s[:value], 'WebPage'), RDF::URI(s[:predicate]), s[:value]]
      elsif s[:rdfs_class_name] == 'ContactPoint'
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/contactPoint'), build_uri(subject,'ContactPoint')]
        graph << [build_uri(subject, 'ContactPoint'), RDF.type, RDF::URI('http://schema.org/ContactPoint')]
        s[:value].make_into_array.each_with_index do |str, index|
          statement = RDF::Statement(build_uri(subject,'ContactPoint'), RDF::URI(s[:predicate]), RDF::Literal(str))
          graph << statement
          graph << [statement,  RDF::URI('http://schema.org/position'), index] if nesting_options[:for_artsdata]
        end
      elsif s[:rdfs_class_name] == 'AggregateOffer'
        graph << [RDF::URI(subject), RDF::URI('http://schema.org/offers'), build_uri(subject,'AggregateOffer')]
        graph << [build_uri(subject,'AggregateOffer'), RDF.type, RDF::URI('http://schema.org/AggregateOffer')]
        s[:value].make_into_array.each do |str|
          graph << [build_uri(subject,'AggregateOffer'), RDF::URI(s[:predicate]), RDF::Literal(str)]
        end
      ## TEMPORARY PATCH  END #########

      elsif  s[:datatype] == 'xsd:anyURI'
        s[:value].each_with_index do |uri, index|
          # check for schema:sameAs and add as string because this is always a string in schema.org
          # but condenser treats it as a URI inorder to link to Artsdata
          # if we don't convert to string we will add back the data from Artsdata in a loop
          uri.sub!('footlight:', 'http://kg.footlight.io/resource/')
          if s[:predicate].include?('sameAs')
            graph << [RDF::URI(subject), RDF::URI(s[:predicate]), RDF::Literal(uri)]
          elsif s[:predicate].include?('location')
            statement = RDF::Statement(RDF::URI(subject), RDF::URI(s[:predicate]), RDF::URI(uri))
            graph << statement
            graph << [statement,  RDF::URI('http://schema.org/position'), index] if nesting_options[:for_artsdata]
          else
            graph << RDF::Statement(RDF::URI(subject), RDF::URI(s[:predicate]), RDF::URI(uri))
          end
        end
      elsif  s[:datatype] == 'xsd:dateTime'
        # Test value and adjust datatype to either xsd:dateTime or xsd:date
        s[:value].make_into_array.each_with_index do |date_time, index|
          if RDF::Literal::DateTime.new(date_time).valid?
           
            statement = RDF::Statement(RDF::URI(subject), RDF::URI(s[:predicate]), RDF::Literal::DateTime.new(date_time))
            graph << statement
            graph << [statement,  RDF::URI('http://schema.org/position'), index]  if nesting_options[:for_artsdata]
            puts "adding dateTime #{statement.inspect}"
          elsif RDF::Literal::Date.new(date_time).valid?
            statement = RDF::Statement(RDF::URI(subject), RDF::URI(s[:predicate]), RDF::Literal::Date.new(date_time))
            graph << statement
            graph << [statement,  RDF::URI('http://schema.org/position'), index]  if nesting_options[:for_artsdata]
          else
            # graph << [RDF::URI(subject), RDF::URI(s[:predicate]), RDF::Literal(date_time)] 
          end
        end
      elsif  s[:datatype] == 'xsd:date'
        # Test value and adjust datatype to either xsd:dateTime or xsd:date
        s[:value].make_into_array.each_with_index do |date_time, index|
          if RDF::Literal::DateTime.new(date_time).valid?
            statement = RDF::Statement(RDF::URI(subject), RDF::URI(s[:predicate]), RDF::Literal::DateTime.new(date_time))
            graph << statement
            graph << [statement,  RDF::URI('http://schema.org/position'), index]  if nesting_options[:for_artsdata]
          elsif RDF::Literal::Date.new(date_time).valid?
            statement = RDF::Statement(RDF::URI(subject), RDF::URI(s[:predicate]), RDF::Literal::Date.new(date_time))
            graph << statement
            graph << [statement,  RDF::URI('http://schema.org/position'), index]  if nesting_options[:for_artsdata]
          else
            # graph << [RDF::URI(subject), RDF::URI(s[:predicate]), RDF::Literal(date_time)] 
          end
        end
      else
        object = if s[:language].present?
                   RDF::Literal(s[:value], language: s[:language])
                 else
                   RDF::Literal(s[:value])
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

  # Get triples about a URI from Artsdata.ca AND Footlight database
  def self.describe_uri(uri)
    query = RDF::Query.new do
      pattern [uri, :p, :o]
    end
    # Get all URI's triples from ArtsdataGraph initialized at startup
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

    # if nothing is found in cached ArtsdataGraph then dereference URI from Artsdata
    if graph.count.zero?
      if uri.value.include?('kg.artsdata.ca/resource/K')
        # dereference URI
        linked_data = dereference_uri(uri)
        if linked_data.class == RDF::Graph
          # remove non-schema vocabulary for types
          sparql = RDFLoader.load_sparql('remove_nonschema_types.sparql')
          sse = SPARQL.parse(sparql, update: true)
          linked_data.query(sse)
          # TODO: keep only english and french languages (MUST for wikidata entries)
          graph << linked_data
          # add to ArtsdataGraph class variable for the lifespan of the server (until restart)
          ArtsdataGraph.graph << linked_data
        end
      end
    end

    graph
  end

  # Derefence URI and return a graph object
  def self.dereference_uri(uri)
    return  RDF::Graph.new unless uri.value.include?('kg.artsdata.ca/resource/K')

    artsdata_id = uri.value.delete_prefix('http://kg.artsdata.ca/resource/')
    begin
      # get ranked dereference
      url = "#{self.artsdata_rank_api_url}#{artsdata_id}?format=jsonld"
      result = HTTParty.get(url)
      # create graph 
      RDF::Graph.new << JSON::LD::API.toRdf(JSON.parse(result.body))
    rescue IOError => e
      Rails.logger.error "Error dereferencing URI: #{uri.inspect}. Exception: #{e.inspect}"
      { error: "IOError", method: 'dereference_uri', message: "#{e.inspect}"}
    rescue StandardError => e
      Rails.logger.error "No server running at: #{artsdata_rank_api_url}. Unable to dereference URI: #{uri.inspect}. Exception: #{e.inspect}"
      { error: "No server running at #{artsdata_rank_api_url}", method: 'dereference_uri', message: "#{e.inspect}"}
    end
  end

  def self.artsdata_rank_api_url
    if Rails.env.development?  || Rails.env.test?
      "http://localhost:#{ARTSDATA_API_PORT}/ranked/"
    else
      'http://api.artsdata.ca/ranked/'
    end
  end
end
