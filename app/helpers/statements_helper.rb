module StatementsHelper

  include CcKgHelper
  include CcWringerHelper
  
  def scrape_sources sources, webpage, scrape_options={}
    logger.info("*** Starting scrape with sources:#{sources.inspect} for webpage: #{webpage.inspect}")
    sources.each do |source|

      #################################################
      # MAIN SCRAPE ACTIVITY
      _scraped_data = scrape(source, @next_step.nil? ? webpage.url :  @next_step, scrape_options)
      #################################################

      if source.next_step.nil?
        @next_step = nil #clear to break chain of scraping urls

        #################################################
        # SECONDARY SCRAPE ACTIVITY - post process
        _data = format_datatype(_scraped_data, source.property, webpage)
        #################################################

        #add startDate to ArchiveDate in Webpages Table to be able to sort by date and refresh event still to come.
        if source.property.uri == "http://schema.org/startDate" && source.selected
          logger.info("*** Setting Last Show Date:#{_data}")
          #TODO: improve error handling to use consistent {error:}
          _data_string = _data&.to_s&.downcase
          if !_data_string.include?('error') && !_data_string.include?('bad')
             _data.class == Array ? last_show_date = _data.last : last_show_date = _data
             if last_show_date.present?
               webpage.archive_date = last_show_date.to_datetime - 24.hours
               if webpage.save
                 logger.debug("*** set archive date for #{webpage.url} to #{webpage.archive_date}")
               else
                 logger.error("*** ERROR: could not save archive date for #{webpage.url} using  #{last_show_date}.")
               end
             end
           end
        end

        s = Statement.where(webpage_id: webpage.id, source_id: source.id)
        #decide to create or update database entry
        if s.count != 1
          Statement.create!(cache:_data, webpage_id: webpage.id, source_id: source.id, status: status_checker(_data, source.property) , status_origin: "condenser_refresh",cache_refreshed: Time.new)
        else
          #check if manual entry and ONLY update if the cache has a status of missing
          if source.algorithm_value.start_with?("manual=") 
            if status_checker(s.first.cache, source.property) != "missing"
              logger.info "Skipping update of manual entry"
              next
            else
              logger.info "Retrying to process manual entry because status is MISSING"
            end
          end

          #preserve manually added and deleted links of datatype xsd:anyURI

           if source.property.value_datatype == "xsd:anyURI" 
            _data = [ _data] if  _data[0].class != Array
            begin
              _old_cache = JSON.parse(s.first.cache)
            rescue => exception
              _old_cache = s.first.cache
            end
            _old_cache = [ _old_cache] if  _old_cache[0].class != Array
            _old_cache.each do |c|
              if c[0] == "Manually added" || c[0] == "Manually deleted" 
                _data << c 
              end
            end
          end
          #update database. Model automatically sets cache changed
          logger.info("*** Last step cache: #{_data}")
          first_statement =  s.first
          if _data&.to_s&.include?('abort_update')
            #set errors
            logger.error "###ERROR IN SCRAPE: Received 'abort_update' during scraping. #{_data}"
          else
            first_statement.update(cache:_data, cache_refreshed: Time.new) 
          end
        end
      else
        #there is another step
        logger.info("*** First step cache: #{_scraped_data}")
        @next_step = _scraped_data.count == 1 ? _scraped_data : _scraped_data.first
      end
    end
  end


  def scrape(source, url, scrape_options={})
   
    algorithm = source.algorithm_value
    if algorithm.start_with?("manual=")
      results_list = [algorithm.delete_prefix("manual=")]
    else
      begin
        agent = Mechanize.new
        agent.user_agent_alias = 'Mac Safari'
        html = agent.get_file  use_wringer(url, source.render_js, scrape_options)
        page = Nokogiri::HTML html
        results_list = []
        algorithm.split(';').each do |a|
          if a.start_with? 'url'
            #replace current page by sraping new url using format url='http://example.com'
            new_url = a.delete_prefix("url=")
            new_url = new_url.gsub("$array","results_list")
            new_url = new_url.gsub("$url","url")
            new_url = eval(new_url)
            logger.info ("*** New URL formed: #{new_url}")
            html = agent.get_file  use_wringer(new_url, source.render_js, scrape_options)
            page = Nokogiri::HTML html
          elsif a.start_with? 'api'
            new_url = a.delete_prefix("api=")
            new_url = new_url.gsub("$array","results_list")
            new_url = new_url.gsub("$url","url")
            new_url = eval(new_url)
            logger.info ("*** New json api URL formed: #{new_url}")
            data = HTTParty.get new_url
            logger.info ("*** api response body: #{data.body}")
            results_list = JSON.parse(data.body)
          elsif a.start_with? 'ruby'
            command = a.delete_prefix("ruby=")
            command.gsub!("$array","results_list")
            command.gsub!("$url","url")
            results_list = eval(command)
          elsif a.start_with? 'xpath_sanitize'
            page_data = page.xpath(a.delete_prefix("xpath_sanitize="))
            page_data.each { |d| results_list << sanitize(d.to_s ,tags: %w(h1 h2 h3 h4 h5 h6 p li ul ol strong em a i br), attributes: %w(href)) }

          elsif a.start_with? 'if_xpath'
            page_data = page.xpath(a.delete_prefix("if_xpath="))
            break if page_data.blank?
            page_data.each { |d| results_list << d.text}

          elsif a.start_with? 'xpath'
            algo = a.delete_prefix("xpath=").gsub("$url",url)
            page_data = page.xpath(algo)
            page_data.each { |d| results_list << d.text}

          elsif  a.start_with? 'css'
            page_data = page.css(a.delete_prefix("css="))
            page_data.each { |d| results_list << d.text}
          elsif  a.start_with? 'time_zone'
            results_list << "time_zone: #{a.delete_prefix('time_zone=')}"
            logger.info ("*** Adding time_zone: #{results_list}")
          end
        end
      rescue => e
        logger.error(" ****************** Error in scrape: #{e.inspect}")
        results_list = [["abort_update"],["error: #{e.inspect}"]]
      end
    end
    return results_list
  end



  def status_checker (scraped_data, property)
    if property.value_datatype == "xsd:anyURI"
      if scraped_data.is_a? String  
        begin
          scraped_data =  JSON.parse(scraped_data) 
        rescue
         scraped_data = []
        end
      end
      if scraped_data[1].is_a? Array
        scraped_data[1].count >= 3 ? status = "initial" : status = "missing"
      elsif scraped_data[0].is_a? Array
          scraped_data[0].count >= 3 ? status = "initial" : status = "missing"
      else
        scraped_data.count >= 3 ? status = "initial" : status = "missing"
      end
    else
      !scraped_data.blank? && !scraped_data&.to_s&.downcase&.include?('error') ? status = "initial" : status = "missing"
    end

    return status
  end

  def is_condenser_formated_array scraped_data
    #check if scraped_data is already formated for condenser as an array in the case of hard coding (like event category).
    # example: scraped_data = ["[\"Manually added\",\"Category\",[\"Performance\" , \"http://ontology.artsdata.ca/Performance\"]]"]
    begin
      if scraped_data[0][0] == "["
        return true
      else
        return false
      end
    rescue => exception
      return false
    end
  end


  def format_datatype (scraped_data, property, webpage)
    data = []
    if property.value_datatype == "xsd:dateTime"
      logger.info("Formatting dateTime with: #{scraped_data}")
      #check for time_zone
      time_zone = nil
      scraped_data.each do |t|
        if t.class == String
          if t.start_with?('time_zone:')
            time_zone = t.split(':')[1].strip
            scraped_data.delete(t)
          end
        end
      end
      scraped_data.each do |t|
        if time_zone
          data << ISO_dateTime(t,time_zone)
        else
          data << ISO_dateTime(t)
        end
      end
    elsif property.value_datatype == "xsd:anyURI"
      if  !scraped_data.blank?
        # first check if scraped_data is already formated as an array, and then parse and skip search.
        if is_condenser_formated_array(scraped_data) 
          #parse URI set mannually
          data = JSON.parse(scraped_data[0])
        else
          # check for eventStatus
          # Note: this code requires the following triple
          # { rdfs:label owl:equivalentProperty schema:name . }
          if property.uri == "http://schema.org/eventStatus" 
            str = scraped_data.join(" - ")
            if str.scan(/\WCancelled/i).present?
              str = "EventCancelled: #{str}"
            elsif str.scan(/\WPostponed/i).present?
              str = "EventPostponed: #{str}"
            elsif str.scan(/\WRescheduled/i).present?
              str = "EventRescheduled: #{str}"
            else
              str = "EventScheduled: No mention of cancelled, postponed or rescheduled in: #{str}."
            end
            data << search_for_uri(str, property, webpage)
          else
            scraped_data.each do |uri_string|
              data << search_for_uri(uri_string, property, webpage)
            end
          end
        end
      end
    elsif property.value_datatype == "xsd:duration"
      scraped_data.each do |t|
        data << ISO_duration(t)
      end
    else
      data = scraped_data
    end
    if data.class == Array
      data = data.first if data.count == 1
    end
    return data
  end

  def search_for_uri uri_string, property_obj, webpage_obj
    #data structure of uri = ['name', 'rdfs_class', ['name', 'uri'], ['name','uri'],...]
    uri_string = uri_string.to_s

    uris = [uri_string]
    #use property object to determine class
    rdfs_class = property_obj.expected_class
    uris << rdfs_class

    if !uri_string.downcase.include?("error")
      #search Culture Creates KG

      cckg_results = search_cckg(uri_string, rdfs_class)
      if cckg_results[:error]
        logger.error("*** search kg ERROR:  #{cckg_results}")
        uris << "abort_update"  #this forces the update to skip when the KG server is down and avoids setting everything to blank
      else
        cckg_results[:data].each do |uri|
          uris << uri
        end
      end
    
      if rdfs_class == "Organization"
       
        cckg_results = search_cckg(uri_string, "Person")
        if cckg_results[:error]
          logger.error("*** search kg ERROR:  #{cckg_results}")
          uris << "abort_update"  #this forces the update to skip when the KG server is down and avoids setting everything to blank
        else
          cckg_results[:data].each do |uri|
            uris << uri
          end
        end
      end
      return uris.uniq
    end

    logger.info("*** search condenser and kg:  #{uris}")
    return uris
  end

  def search_condenser uri_string, expected_class #returns a HASH
    # get names of all statements of expected_class
    hits = []
    #statements = Statement.where(cache: uri_string)
    entities = Statement.joins(source: :property).where({sources: { properties: {label: "Name", rdfs_class: RdfsClass.where(name: expected_class)}}}).pluck(:cache,:webpage_id)
    entities.each {|entity| hits << entity if uri_string.downcase.include?(entity[0].downcase)}


    # get uris for found places
    hits.each_with_index do |hit,index|
      webpage = Webpage.find(hit[1])
      if webpage
        hits[index][1] = webpage.rdf_uri
      end
    end
    return {data: hits.uniq}
    ##TODO: ????also check (s.webpage.website == webpage.website)
  end


  def search_cckg str, rdfs_class #returns a HASH
    if str.length > 3 
     
      sparql_str = str.gsub( /'/, "\\\\'") #escape single quote so it does not interfere with SPARQL 
                      .gsub(/\u00A0/i," ")  #remove &nbsp;
     
      sparql_str = CGI::unescapeHTML(sparql_str) #get rid of things like &amp; in the text string

      if rdfs_class == "Place"
        q = 
        <<~EOS
          PREFIX schema: <http://schema.org/>       
          select  ?uri ?name   
          { { select ?uri ?name where {   
                  ?uri a schema:Place ; schema:name ?name .
                  OPTIONAL { ?uri schema:alternateName ?alternateName .}     
                  values ?web_str {'#{sparql_str}'}   
                  filter (contains(lcase(?web_str), lcase(str(?name))) || contains(lcase(?web_str), lcase(str(?alternateName)))  )  
                  filter  (isURI(?uri)) 
                  } }  
            MINUS   
            {select ?uri  where { 
                   ?smallPlace a schema:Place ; schema:name ?name ; schema:alternateName ?alternateName; schema:containedInPlace ?uri  . 
                   values ?web_str {'#{sparql_str}'}   
                   filter (contains(lcase(?web_str), lcase(str(?name))) || contains(lcase(?web_str), lcase(str(?alternateName)))  ) 
                 }   }}
          EOS
      else
      
        q = 
        <<~EOS
          PREFIX schema: <http://schema.org/>       
          select  ?uri  ?name      
          where {        
              { ?uri a schema:#{rdfs_class}; schema:alternateName ?search_str ; schema:name ?name . }             
              UNION   
              { ?uri a schema:#{rdfs_class}; schema:name ?search_str, ?name .  }      
              UNION   
              { ?uri a schema:#{rdfs_class}; schema:url ?search_str ; schema:name ?name .  }    
              filter  (isURI(?uri))   
              filter (str(?search_str) != '')    
              values ?web_str {'#{sparql_str}'}   
              filter (contains(lcase(str(?search_str)),lcase(?web_str)) || contains(lcase(?web_str), lcase(str(?search_str)))  )    
            }  
          EOS

      end

      logger.info "SPARQL: #{q}"
      results = cc_kg_query(q, rdfs_class)
    
      if !results[:error]
        hits = results[:data].clone
        logger.info " ++++++++++++=Hits from cc_kg_query: #{hits}"
        hits.count.times do |n|
          if !hits[n].blank?
            hits[n] = [hits[n]["name"]["value"],hits[n]["uri"]["value"]]
          end
        end
        ###only return hit if the name is unique #todo: find a way to remove owl:sameAS when the same entity has more than 1 URI
        hits.uniq! {|hit| hit[0]}

        ## remove duplicate URIs - needed to remove en/fr duplicates and alternte names of same entity
        hits.uniq! {|hit| hit[1]}

        #################################################
        # REMOVE NAMES THAT CREATE MANY FALSE POSITIVES - until better analysis with NLP is available 
        names_to_remove = SearchException.where(rdfs_class: RdfsClass.where(name: rdfs_class)).pluck(:name)
        hits.select! { |hit| !names_to_remove.include? hit[0] }
        #################################################

        return {data: hits}
      else
        return {error: results, method: "search_cckg"} #with error message
      end
    else
      return {error: "String '#{str} is too short. Needs to be londer than 2 characters", method: "search_cckg"} #with error message
    end
  end


  def ISO_duration(duration_str)
    begin
      duration_in_seconds = ChronicDuration.parse(duration_str)
      if duration_in_seconds.blank?
        duration_iso8601 = "No duration found: #{duration_str}"
      else
        duration_iso8601 = "PT#{duration_in_seconds}S"
      end
    rescue
      duration_iso8601 = "Error in duration: #{duration_str}"
    end
    return duration_iso8601
  end

  def french_to_english_month(date_time)
    date_time.downcase
    .gsub(/janvier|février|fév|mars|avr|mai|juin|juillet|juil|août|aou|aoû|septembre|octobre|novembre|décembre|déc/, 'janvier'=> 'JAN', 'février'=> 'FEB', 'fév'=> 'FEB', 'mars'=> 'MAR', 'avril'=> 'APR', 'avr'=> 'APR', 'mai'=>'MAY', 'juin' => 'JUN', 'juillet' => 'JUL','juil' => 'JUL','aou'=>'AUG', 'août'=>'AUG', 'aoû'=>'AUG','septembre'=> 'SEP','octobre'=> 'OCT','novembre'=> 'NOV','décembre'=>'DEC', 'déc'=>'DEC')
  end

  def ISO_dateTime(date_time, time_zone = "Eastern Time (US & Canada)" )
    begin
      current_timezone = Time.zone
      Time.zone = time_zone
      d = Time.zone.parse(self.french_to_english_month(date_time)
                               .gsub(/ h /, 'h')  # French times usually have spaces around the 'H'
                               .gsub(/halifax/i, '')) # Halifax is used in timezone names. Remove it to avoid confusion.
      
      # if the dateTime is midnight then assume that there is no known time and convert to a Date Object instead of Time object.
      if d == d.midnight
        d = d.to_date
      end
      
      Time.zone = current_timezone

      iso_date_time =  d.iso8601
    rescue => e
      iso_date_time = "Bad input date_time: #{date_time} with error: #{e.inspect}"
    end
    return iso_date_time
  end

  def format_language language
    "@" + language if !language.blank?
  end

  def build_key statement # for JSON output
      new_key = statement.source.property.label.downcase.sub(" ","_")
      new_key = "#{new_key}_#{statement.source.language}" if !statement.source.language.blank?
      return new_key
  end


  def process_linked_data_removal statement_cache, uri_to_delete, class_to_delete, label_to_delete


        statement_cache = [statement_cache] if statement_cache[0].class != Array
     
        updated_cache = false
        statement_cache.each_with_index do |c,i|
         
            if (c[0] == "Manually deleted" || c[0] == "Manually added")
              c.each_with_index do |uri_pair,x|
               if uri_pair[1] == uri_to_delete
                  statement_cache[i].delete_at(x) 
                  updated_cache = true
               end
              end
              statement_cache.delete_at(i) if c.length < 3
            end
          
        end

        #if no change then store the link to delete
        if !updated_cache

          link_added = false
          statement_cache.each_with_index do |c,i|
            if c[0] == "Manually deleted" 
              statement_cache[i] << [label_to_delete, uri_to_delete]
              link_added = true
            end
          end
          if !link_added 
            statement_cache << ["Manually deleted",class_to_delete, [label_to_delete, uri_to_delete]]
          end
        
        end

        return statement_cache
      end

end
