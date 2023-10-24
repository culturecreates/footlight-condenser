# Local copy of the relevant graphs in Artsdata.ca including Culture Creates curated People, Places, Organizations
class ArtsdataGraph
  
  def self.graph
    @@graph ||= cache_graph
  end

  def self.cache_graph
    @@schema = RDF::Vocabulary.new('http://schema.org/')

    if Rails.env.test? || Rails.env.development?
      @@graph = RDF::Graph.load('test/fixtures/files/artsdata-dump.nt',
                                        format: :nquads)
    else
      # Load artsdata.ca graphs for places, people and organizations
      @@graph =
        RDF::Graph.load('https://db.artsdata.ca/repositories/artsdata/statements?context=%3Chttp%3A%2F%2Fkg.artsdata.ca%2Fminted%2FK11%3E&context=%3Chttp%3A%2F%2Fkg.artsdata.ca%2FOrganization%3E&context=%3Chttp%3A%2F%2Fkg.artsdata.ca%2FPerson%3E',
                        format: :nquads)
      # To create a new dump use:
      # File.open("artsdata-dump.nt", "w") {|f| f << @@artsdata_graph.dump(:ntriples)}
    end
  
    ## replace this with loading schema.org ontology in the future
    ## Instances of EventStatusType
    @@graph  << [RDF::URI("http://schema.org/EventScheduled"), RDF.type, RDF::URI("http://schema.org/EventStatusType")] 
    @@graph  << [RDF::URI("http://schema.org/EventRescheduled"), RDF.type, RDF::URI("http://schema.org/EventStatusType")] 
    @@graph  << [RDF::URI("http://schema.org/EventPostponed"), RDF.type, RDF::URI("http://schema.org/EventStatusType")] 
    @@graph  << [RDF::URI("http://schema.org/EventMovedOnline"), RDF.type, RDF::URI("http://schema.org/EventStatusType")] 
    @@graph  << [RDF::URI("http://schema.org/EventCancelled"), RDF.type, RDF::URI("http://schema.org/EventStatusType")] 

    ## Load local entities (People, Places, Organizations) entered manually into Footlight
    local_graph = LocalGraphGenerator.graph_all
    # puts "Local graph: #{local_graph.dump(:ntriples)}"
    @@graph << local_graph
  end
  
end
