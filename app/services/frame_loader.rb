# Class to manage JSON framing for JSON-LD manipulation
class FrameLoader
  def self.load(main_class, lang)

    file_name = 
      case main_class
      when 'Event'
        'app/services/frames/event.json'
      when 'Place'
        'app/services/frames/place.json'
      else
        nil
      end

    return unless file_name

    frame = File.read(file_name)

    case lang
    when 'fr'
      frame.gsub!('"@language": "en"', '"@language": "fr"')
    when 'en'
      frame
    end

    JSON.parse(frame)
  end
end
