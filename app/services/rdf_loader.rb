# Class to load RDF related files for JSON-LD Framing and SPARQL
class RdfLoader
  # Loads a JSON-LD frame based on Class parameter
  def self.load_frame(main_class)
    file_name =
      case main_class
      when 'Event'   then 'app/services/frames/event.jsonld'
      when 'Place'   then 'app/services/frames/place.jsonld'
      end

    return unless file_name

    JSON.parse(File.read(file_name))
  end

  # Loads a SPARQL and performs substitution 
  # substitute_list =["target 1","substitue 1", "target 2", "substitute 2"]
  def self.load_sparql(file_name, substitute_list = [])
    f = File.read("app/services/sparqls/#{file_name}")
    substitute_list.each_slice(2) do |a, b|
      f.gsub!(a, b)
    end
    f
  end
end
