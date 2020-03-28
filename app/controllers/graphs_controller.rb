class GraphsController < ApplicationController
    before_action :preload_context, only: [:webpage_event]

    require 'json/ld'  

    @@schema = RDF::Vocabulary.new("http://schema.org/")
    
    if Rails.env.test?
        puts "loading artsdata graph from test/fixtures/files"
        @@artsdata_graph = RDF::Graph.load("test/fixtures/files/artsdata-dump.nt", format: :nquads)
    else
        #use class graph with artsdata places, people and organizations
        @@artsdata_graph = 
        RDF::Graph.load("https://db.artsdata.ca/repositories/artsdata/statements?context=%3Chttp%3A%2F%2Fkg.artsdata.ca%2FPlace%3E&context=%3Chttp%3A%2F%2Fkg.artsdata.ca%2FOrganization%3E&context=%3Chttp%3A%2F%2Fkg.artsdata.ca%2FPerson%3E", format: :nquads)
        #File.open("artsdata-dump.nt", "w") {|f| f << @@artsdata_graph.dump(:ntriples)}
    end

    ## replace this with loading schema.org ontology in the future
    ## Instances of EventStatusType
    @@artsdata_graph  << [RDF::URI("https://schema.org/EventScheduled"), RDF.type, RDF::URI("http://schema.org/EventStatusType")] 
    @@artsdata_graph  << [RDF::URI("https://schema.org/EventRescheduled"), RDF.type, RDF::URI("http://schema.org/EventStatusType")] 
    @@artsdata_graph  << [RDF::URI("https://schema.org/EventPostponed"), RDF.type, RDF::URI("http://schema.org/EventStatusType")] 
    @@artsdata_graph  << [RDF::URI("https://schema.org/EventMovedOnline"), RDF.type, RDF::URI("http://schema.org/EventStatusType")] 
    @@artsdata_graph  << [RDF::URI("https://schema.org/EventCancelled"), RDF.type, RDF::URI("http://schema.org/EventStatusType")] 

    ## Instances of EventAttendanceModeEnumeration 
    @@artsdata_graph  << [RDF::URI("https://schema.org/OfflineEventAttendanceMode"), RDF.type, RDF::URI("http://schema.org/EventAttendanceModeEnumeration")] 
    @@artsdata_graph  << [RDF::URI("https://schema.org/OnlineEventAttendanceMode"), RDF.type, RDF::URI("http://schema.org/EventAttendanceModeEnumeration")] 
    @@artsdata_graph  << [RDF::URI("https://schema.org/MixedEventAttendanceMode"), RDF.type, RDF::URI("http://schema.org/EventAttendanceModeEnumeration")] 


    #GET /graphs/:rdf_uri
    def show
        webpages = Webpage.where(rdf_uri:params[:rdf_uri] )
        statements = transform_statements_for_graph(webpages)

        @local_graph =  build_graph_from_condenser_statements(params[:rdf_uri], statements)
        graph = @@artsdata_graph
        graph <<  @local_graph
          
        #frame JSON-LD
        json_graph = JSON.parse(graph.dump(:jsonld))
        @jsonld = JSON::LD::API.frame(json_graph, frame())

        # remove context because Google doesn't like extra types
        @google_jsonld = make_google_jsonld(@jsonld)
    end

    #GET /graphs/webpage/event?url=
    def webpage_event
        webpage = Webpage.where(url: CGI.unescape(params[:url] ))
        rdf_uri = webpage.first.rdf_uri
        webpages = Webpage.where(rdf_uri: rdf_uri)
        if webpages.present?
            #get statements linked to the webpage that have selected sources.
            statements = Statement.joins({source: :property}).where(webpage_id: webpages, sources: {selected: true} )
            problem_statements = helpers.missing_required_properties(statements)
            if problem_statements.blank?
              
                statements_for_graph =  transform_statements_for_graph(statements)
                @local_graph =  build_graph_from_condenser_statements(rdf_uri, statements_for_graph, {1 => {5 => "http://schema.org/offers"}})

                #add to graph using triples with rdf_uri subject
                uris = extract_object_uris(@local_graph)
                uris.each do |uri|
                    @local_graph << describe_uri(uri)
                end
                
                #frame JSON-LD
                json_graph = JSON.parse(@local_graph.dump(:jsonld))
                @jsonld = JSON::LD::API.frame(json_graph, frame(webpage.first.language)) 
              
                # remove context because Google doesn't like extra types
                @google_jsonld = make_google_jsonld(@jsonld)
            else
                problems_summary = problem_statements.map{|s| s.source.property.label}.join(", ")
                @google_jsonld = {"messsage" => "Event needs review in Footlight console. Issues with #{problems_summary}."}.to_json
            end
        else
            @google_jsonld = {"messsage" => "Webpage fits URL pattern but is missing from Footlight console."}.to_json
        end

        logger.info("### Code Snippet Call /graphs/webpage/event?url=#{params[:url]}")
        respond_to do |format|
            format.html {  }
            format.jsonld { render inline: @google_jsonld, content_type: 'application/ld+json' }
        end
    end



    private
   

        def transform_statements_for_graph statements
            #create a HASH for each statements {status:,rdfs_class:,predicate:,object:,language:,value_datatype:,label:}
            statements_hash = statements.map { |s| {status: s.status, rdfs_class: s.source.property.rdfs_class_id, predicate: s.source.property.uri, object: s.cache, language: s.source.language, value_datatype: s.source.property.value_datatype, label: s.source.property.label} } 
            #map statements that have a datatype xsd:anyURI to a list of URIs
            statements_hash.map {|s|  s[:object] = extract_uri(s[:object]) if s[:value_datatype] == "xsd:anyURI"  }
            #remove any blank statements
            statements_hash.select! {|s| s[:object].present? && s[:object] != "[]"}
            return statements_hash
        end

        def extract_uri cache
            cache_obj =  helpers.build_json_from_anyURI(cache)
            return cache_obj.pluck(:links).flatten.pluck(:uri)
        end

        def make_google_jsonld jsonld
            return jsonld["@graph"][0].merge("@context" => "http://schema.org").to_json
        end

        def build_graph_from_condenser_statements rdf_uri, statements, nesting_options
            graph = RDF::Graph.new

            subject = rdf_uri.sub("adr:", "http://kg.artsdata.ca/resource/" )
            #TODO: Make generic - not only Event Class. 
            # Interpret the nesting_options, 
            # create main Class and blank nodes for each nested class 
            # and set subject first thing inside loop.
            graph << [RDF::URI(subject), RDF.type, RDF::URI("http://schema.org/Event")]
            statements.each do |s|
                ## TEMPORARY PATCH START #########
                if s[:rdfs_class] == 5 
                    graph << [RDF::URI(subject), RDF::URI("http://schema.org/offers"), :bn ]
                    graph << [ :bn,  RDF.type,  RDF::URI("http://schema.org/Offer")]
                    graph << [ :bn, RDF::URI(s[:predicate]), RDF::Literal(s[:object], language: s[:language])]
                elsif s[:rdfs_class] == 41 
                    graph << [RDF::URI(subject), RDF::URI("http://schema.org/eventStatus"), :bn ]
                    graph << [ :bn,  RDF.type,  RDF::URI("http://schema.org/EventStatusType")]
                    graph << [ :bn, RDF::URI(s[:predicate]), RDF::URI(s[:object])]
                ## TEMPORARY PATCH  END #########
                elsif  s[:value_datatype] == "xsd:anyURI"
                    s[:object].each do |uri|
                        graph << [RDF::URI(subject), RDF::URI(s[:predicate]), RDF::URI(uri)] 
                        #add describe URI to graph  
                    end
                elsif  s[:value_datatype] == "xsd:dateTime"
                    if  s[:object][0] == "["
                        dateTimeArray = JSON.parse(s[:object]) 
                    else
                        dateTimeArray = [s[:object]] 
                    end
                    if dateTimeArray
                        dateTimeArray.each do |dateTime|
                            if RDF::Literal::DateTime.new(dateTime).valid?
                            graph << [RDF::URI(subject), RDF::URI(s[:predicate]), RDF::Literal::DateTime.new(dateTime)] 
                            end
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
            return graph
        end

        def extract_object_uris graph
            query = RDF::Query.new do
                pattern [:s, :p,  :object]
            end
            solutions = query.execute(graph)
            solutions.filter! { |solution| solution.object.uri? }

            uri_list = []
            solutions.each{|s| uri_list  << s.to_h[:object]}
            return uri_list
        end

        def describe_uri uri
        
            query = RDF::Query.new do
                pattern [uri, :p,  :o]
            end
            result = query.execute(@@artsdata_graph)
            g = RDF::Graph.new
            result.each do |s|
                g << [uri, s.to_h[:p], s.to_h[:o]]
                if s.to_h[:o].node?
                    ## Add blank nodes in object position to expand describe for location which contains a blank node for address.
                    query2 = RDF::Query.new do
                        pattern [s.to_h[:o], :bnp,  :bno]
                    end
                    result2 = query2.execute(@@artsdata_graph)
                    result2.each {|bns|  g << [s.to_h[:o], bns.to_h[:bnp], bns.to_h[:bno]]}
                end
                
             end 
             return g

        end



        def sparql_multiple_dates uri_string
            return
            <<~EOS
            PREFIX schema: <http://schema.org/>

            construct {
                ?uri schema:subEvent
                    [ a schema:Event  ; 
                    schema:name ?name ; 
                    schema:description ?description ;
                    schema:startDate ?dates ;
                    schema:location ?location ]
            }
            where { 
                ?uri schema:description ?description ; 
                schema:location ?location ;
                schema:name ?name .
                    { select ?dates where {
                        values ?uri { <#{uri_string}> }
                        ?uri  schema:startDate ?dates
                    }
                } 
            }
            EOS


        end


        def frame lang
            if lang == "en" || lang == "fr"
                frame_string = 
                <<~EOS
                    {
                    "@context":
                        {
                            "@vocab": "http://schema.org/",
                            "startDate": {"@type":  "http://www.w3.org/2001/XMLSchema#dateTime"},
                            "description" : {"@id":"description","@language": "#{lang}" },
                            "url":  {"@id":"url","@language": "#{lang}" },
                            "name": {"@id":"name","@language": "#{lang}"},
                            "alternateName": {"@id":"alternateName","@language": "#{lang}"},
                            "image": {"@id":"image","@language": "#{lang}"}
                        },
                    "@type": "Event",
                    "@explicit": true,
                    "name": {"@value":{},"@language": "#{lang}"} ,
                    "startDate" :{},
                    "description" :{"@value":{},"@language": "#{lang}"},
                    "duration": {"@value":{}},
                    "url":{"@value":{},"@language": "#{lang}"},
                    "eventStatus":{},
                    "eventAttendanceMode":{},
                    "location": {
                        "@type":"Place", 
                        "@explicit": true,
                        "name": {"@value":{},"@language": "#{lang}"} ,
                        "address": {
                            "@type":"PostalAddress",
                            "@explicit": false
                        }
                    },
                    "performer":{
                            "@type": ["Organization","Person"],
                            "@explicit": false,
                            "name": [{"@value":{}},{"@value":{},"@language": "#{lang}"}] ,
                            "sameAs":{},
                            "url":{},
                            "alternateName":[{"@value":{},"@language": "#{lang}"}]
                        },
                    "image":{},
                    "offers": {
                        "@type": "Offer"
                    }
                }
                EOS
                return JSON.parse(frame_string)
            end
        end
end
