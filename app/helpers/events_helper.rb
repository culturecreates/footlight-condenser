module EventsHelper


    def parse_date_string_array date_str
        #dates_array can be in the form "2020-05-06T19:30:00-04:00" or "[\"2019-11-16T21:00:00-05:00\", \"2019-11-16T23:30:00-05:00\"]"
  
        #step 1: convert stringified array to a singe date 
        if date_str[0] == "[" 
            date_array = JSON.parse(date_str)
        else
            date_array = [date_str]
        end
  
        #step 2: convert to time
        date_array.map! do |date_time|

            begin
                date_time = DateTime.parse(date_str)
            rescue => exception
                logger.info("Invalid Event Date: #{exception}")
                date_time = nil
            end
        end
        first_valid_date_time = date_array.first
        if first_valid_date_time.blank?
            first_valid_date_time = patch_invalid_date
        end
        return first_valid_date_time
    end


      
    def patch_invalid_date
        return  DateTime.now + 1.year
    end
end
