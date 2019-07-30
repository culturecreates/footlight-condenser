module StatementsHelper

  include CcKgHelper

  def scrape(source, url, scrape_options={})

    algorithm = source.algorithm_value
    if algorithm.start_with?("manual=")
      results_list = [algorithm.delete_prefix("manual=")]
    else
      begin
        agent = Mechanize.new
        agent.user_agent_alias = 'Mac Safari'
        if @html_cache[0] == url &&  @html_cache[1] == source.render_js
          html = @html_cache[2]
        else
          html = agent.get_file  use_wringer(url, source.render_js, scrape_options)
          @html_cache = [url, source.render_js, html]
        end

        page = Nokogiri::HTML html
        results_list = []
        logger.info ("*** Algorithm split: #{algorithm.split(';')}")
        algorithm.split(';').each do |a|
          logger.info ("*** Algorithm: #{a}")
          if a.start_with? 'url'
            #replace current page by sraping new url
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
            logger.info("***  algorithm: #{a} RESULT => #{page_data} ")
          elsif a.start_with? 'if_xpath'
            page_data = page.xpath(a.delete_prefix("if_xpath="))
            break if page_data.blank?
            page_data.each { |d| results_list << d.text}
            logger.info("***  algorithm: #{a} RESULT => #{page_data} ")
          elsif a.start_with? 'xpath'
            page_data = page.xpath(a.delete_prefix("xpath="))
            page_data.each { |d| results_list << d.text}
            logger.info("***  algorithm: #{a} RESULT => #{page_data} ")
          elsif  a.start_with? 'css'
            page_data = page.css(a.delete_prefix("css="))
            page_data.each { |d| results_list << d.text}
            logger.info("***  algorithm: #{a} RESULT => #{page_data} ")
          end
        end
      rescue => e
        logger.error(" ****************** Error in scrape: #{e.inspect}")
        results_list = [["Error scrapping"],["error: #{e.inspect}"]]
      end
    end
    return results_list
  end



  def status_checker (scraped_data, property)
    if property.value_datatype == "xsd:anyURI"
      #check for 2 items in list
      scraped_data.count == 3 ? status = "initial" : status = "missing"
    else
      !scraped_data.blank? && !scraped_data&.to_s&.downcase&.include?('error') ? status = "initial" : status = "missing"
    end

    return status
  end


  def format_datatype (scraped_data, property, webpage)
    data = []
    if property.value_datatype == "xsd:dateTime"
      scraped_data.each do |t|
        data << ISO_dateTime(t)
      end
    elsif property.value_datatype == "xsd:anyURI"
      scraped_data.each do |uri_string|
        data << search_for_uri(uri_string,property,webpage)
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

    #search condenser database
    results = search_condenser(uri_string, rdfs_class)
    results[:data].each do |uri|
      uris << uri
    end
    logger.info("*** search condenser:  #{uris}")

    if uris.count == 2 #then no matches found yet, keep looking
      #search Culture Creates KG
      cckg_results = search_cckg(uri_string, rdfs_class)
      if cckg_results[:error]
          uris << "abort_update"  #this forces the update to skip when the KG server is down and avoids setting everything to blank
      else
        cckg_results[:data].each do |uri|
          uris << uri
        end
      end
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
    q = "PREFIX schema: <http://schema.org/>            \
        select  ?uri  ?name where {              \
	          ?uri a schema:#{rdfs_class} .                \
            ?uri schema:name ?name_lang .                    \
            filter  (isURI(?uri))   \
             bind (str(?name_lang) as ?name) \
            filter (regex(\"#{str}\",?name,\"i\"))  \
         } "
    results = cc_kg_query(q, rdfs_class)
    hits = []
    if !results[:error]
      results[:data].each {|entity|  hits << entity if str.downcase.include?(entity["name"]["value"].downcase)}
      hits.count.times do |n|
        hits[n] = [hits[n]["name"]["value"],hits[n]["uri"]["value"]]
      end
      return {data: hits.uniq {|hit| hit[1]}}
    else
      return {error: results, method: "search_cckg"} #with error message
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
    date_time.downcase.gsub(/ h /, 'h').gsub(/janvier|février|fév|mars|avr|mai|juin|juillet|août|aou|aoû|septembre|octobre|novembre|décembre|déc/, 'janvier'=> 'JAN', 'février'=> 'FEB', 'fév'=> 'FEB', 'mars'=> 'MAR', 'avril'=> 'APR', 'avr'=> 'APR', 'mai'=>'MAY', 'juin' => 'JUN', 'juillet' => 'JUL','aou'=>'AUG', 'août'=>'AUG', 'aoû'=>'AUG','septembre'=> 'SEP','octobre'=> 'OCT','novembre'=> 'NOV','décembre'=>'DEC', 'déc'=>'DEC')
  end

  def ISO_dateTime(date_time)
    begin
      current_timezone = Time.zone
      Time.zone = "Eastern Time (US & Canada)"

      d = Time.zone.parse(self.french_to_english_month(date_time))
      Time.zone = current_timezone

      iso_date_time =  d.iso8601
    rescue
      iso_date_time = "Bad input date_time: #{date_time}"
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

end
