# Class to manage JSON framing for JSON-LD manipulation
class SparqlLoader
  @@sparql = File.read('app/services/sparqls/event_series.sparql')

  def self.sparql
    @@sparql
  end
end