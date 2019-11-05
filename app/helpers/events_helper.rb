module EventsHelper


    def parse_date_string_array date_str
        #dates_array can be in the form "2020-05-06T19:30:00-04:00" or "[\"2019-11-16T21:00:00-05:00\", \"2019-11-16T23:30:00-05:00\"]"
  
        #step 1: convert stringified array to a singe date 
        if date_str[0] == "[" 
            date_str = JSON.parse(date_str)[0]
        end
  
        #step 2: convert to time
        date_time = DateTime.now + 1.year
        if date_str.present?
            begin
                date_time = DateTime.parse(date_str)
            rescue => exception
                logger.error("Invalid Event Date: #{exception}")
            end
        end
        return date_time
    end

      

end
