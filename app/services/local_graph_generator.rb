# Class to load database statements into a RDF Graph
class LocalGraphGenerator
  # main method to dump all local statements into a graph
  def self.graph_all
    graphs = RDF::Graph.new
    graphs << graph_class('Place')
    graphs << graph_class('Organization')
    graphs << graph_class('Person')
    graphs
  end

  # method to build a graph with all triples for a specific rdf class
  def self.graph_class(rdf_class = 'Place')
    rdf_class_id = RdfsClass.where(name: rdf_class).first

    # get all webpages with main entity = rdf_class
    webpages = Webpage.where(rdfs_class: rdf_class_id)

    # get all statements related to webpages and that have selected = true
    statements = Statement.joins({ source: :property }).where(webpage_id: webpages, sources: { selected: true })

    graph = RDF::Graph.new
    graph << generator.build_graph(statements)
    graph
  end

  def self.generator
    @generator ||= JsonldGenerator
  end
end
