module WebpagesHelper

  def attempt_json_parse_on_array  str
    begin
      if str[0] != "["
        str = "[\"#{str}\"]"   #this is needed because the date can be an array or string if only one date
      end
      array = JSON.parse(str)

    rescue
      array =  []
    end
      puts "attempt_json_parse_on_array: #{str} to array #{array}"
    return array
  end

end
