# Class to manage JSON framing for JSON-LD manipulation
class FrameLoader

  def self.load(main_class, lang)

    if main_class == "Event"
      file = 'app/services/frames/event.json'
      case lang
      when 'fr'
        JSON.parse(File.read(file)
          .gsub!('"@language": "en"', '"@language": "fr"'))
      when 'en'
        JSON.parse(File.read(file))
      else
        { error: "Unsupported language: #{lang}" }
      end
    else
      return nil
    end
  end
end
