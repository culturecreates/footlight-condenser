# Class to manage JSON framing for JSON-LD manipulation
class FrameLoader
  file = 'app/services/frames/event.json'
  @@event_en = JSON.parse(File.read(file))
  @@event_fr = JSON.parse(File.read(file)
                              .gsub!('"@language": "en"', '"@language": "fr"'))

  def self.event(lang)
    case lang
    when 'fr'
      @@event_fr
    when 'en'
      @@event_en
    else
      { error: "Unsupported language: #{lang}" }
    end
  end
end
