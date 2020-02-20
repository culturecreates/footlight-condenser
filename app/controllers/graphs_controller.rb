class GraphsController < ApplicationController
    before_action :preload_context, only: [:webpage_event]

    require 'rdf/nquads'  #needed to load statements from graphDB
    require 'json/ld'  

    @@schema = RDF::Vocabulary.new("http://schema.org/")
    #use class graph with artsdata places, people and organizations
    @@artsdata_graph = RDF::Graph.load("https://db.artsdata.ca/repositories/artsdata/statements?context=%3Chttp%3A%2F%2Fkg.artsdata.ca%2FPlace%3E&context=%3Chttp%3A%2F%2Fkg.artsdata.ca%2FOrganization%3E", format: :nquads)
   
    puts "loading base graph"
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
        statements = transform_statements_for_graph(webpage)

        @local_graph =  build_graph_from_condenser_statements(rdf_uri, statements)
     
        #add to graph using triples with rdf_uri subject
        uris = extract_object_uris(@local_graph)
        uris.each do |uri|
            @local_graph << describe_uri(uri)
        end
          
        #frame JSON-LD
        json_graph = JSON.parse(@local_graph.dump(:jsonld))
        @jsonld = JSON::LD::API.frame(json_graph, frame()) 

        # remove context because Google doesn't like extra types
        @google_jsonld = make_google_jsonld(@jsonld)

        respond_to do |format|
            format.html {  }
            format.jsonld { render inline: @google_jsonld, content_type: 'application/ld+json' }
        end
    end



    private
        def extract_uri cache
            cache_obj =  helpers.build_json_from_anyURI(cache)
            return cache_obj.pluck(:links).flatten.pluck(:uri)
        end

        def transform_statements_for_graph webpages
            statements = Statement.joins({source: :property}).where(webpage_id: webpages, sources: {selected: true} ).map { |s| {predicate: s.source.property.uri, object: s.cache, language: s.source.language, value_datatype: s.source.property.value_datatype, label: s.source.property.label} } 
            statements.map {|s|  s[:object] = extract_uri(s[:object]) if s[:value_datatype] == "xsd:anyURI"  }
            statements.select! {|s| s[:object].present? && s[:object] != "[]"}
            return statements
        end

        def make_google_jsonld jsonld
            return jsonld["@graph"][0].merge("@context" => "http://schema.org").to_json
        end

        def build_graph_from_condenser_statements rdf_uri, statements
            graph = RDF::Graph.new

            subject = rdf_uri.sub("adr:", "http://kg.artsdata.ca/resource/" )
            #TODO: Make generic - not only Event Class. Group by Class and preocess each class group.
            graph << [RDF::URI(subject), RDF.type, RDF::URI("http://schema.org/Event")]
            statements.each do |s|
                if  s[:value_datatype] == "xsd:anyURI"
                    s[:object].each do |uri|
                        graph << [RDF::URI(subject), RDF::URI(s[:predicate]), RDF::URI(uri)] 
                        #add decribe URI to graph  
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
            ## todo: Add blank nodes in object position to expand describe for location which contains a blank node for address.
             
             result = query.execute(@@artsdata_graph)
             g = RDF::Graph.new
             result.each {|s| g << [uri, s.to_h[:p], s.to_h[:o]]}
             return g

        end


        def frame
            return  JSON.parse %(
                {
                "@context":
                    {
                        "@vocab": "http://schema.org/",
                        "startDate": {"@type":  "http://www.w3.org/2001/XMLSchema#dateTime"},
                        "description" : {"@id":"description","@language":"en"},
                        "url":  {"@id":"url","@language":"en"},
                        "name": {"@id":"name","@language":"en"}
                    },
                "@type": "Event",
                "@explicit": true,
                "name": {"@value":{},"@language": "en"} ,
                "startDate" :{},
                "description" :{"@value":{},"@language": "en"},
                "duration": {"@value":{}},
                "url":{"@value":{},"@language": "en"},
                "location": {
                    "@type":"Place", 
                    "@explicit": true,
                    "name": {"@value":{},"@language": "en"} ,
                    "address": {
                        "@type":"PostalAddress"
                    }
                },
                "performer":{
                    "@type": "Organization",
                    "@explicit": true,
                    "@type":"Organization",
                    "name": {"@value":{},"@language": "en"} ,
                    "sameAs":{}
                },
                "image":{}
            }
            )
        end
end
