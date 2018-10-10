module StatementsHelper

  def scrape(source, url)
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
          html = agent.get_file  use_wringer(url, source.render_js)
          @html_cache = [url,source.render_js,html]
        end
        page = Nokogiri::HTML html
        results_list = []
        algorithm.split(';').each do |a|
          if a.start_with? 'url'
            #replace current page by sraping new url
            new_url = eval(a.delete_prefix("url=").gsub!("$url","url"))
            logger.info ("*** New URL formed: #{new_url}")
            html = agent.get_file  use_wringer(new_url, source.render_js)
            page = Nokogiri::HTML html
          elsif a.start_with? 'ruby'
            command = a.delete_prefix("ruby=")
            command.gsub!("$array","results_list")
            command.gsub!("$url","url")
            results_list = eval(command)
          else
            page_data = page.xpath(a.delete_prefix("xpath=")) if a.start_with? 'xpath'
            page_data = page.css(a.delete_prefix("css="))   if a.start_with? 'css'
            page_data.each { |d| results_list << d.text}
            logger.info("***  algorithm: #{a} RESULT => #{page_data} ")
          end
        end
      rescue => e
        logger.error(" ****************** Error in scrape: #{e.inspect}")
        results_list = ["Error scrapping"]
      end
    end
    return results_list
  end


  def use_wringer(url, render_js)
    url = url.first if url.class == Array
    escaped_url = CGI.escape(url)
    _base_url = "http://footlight-wringer.herokuapp.com"
    if render_js
      path = "/websites/wring?uri=#{escaped_url}&format=raw&include_fragment=true&use_phantomjs=true"
    else
      path = "/websites/wring?uri=#{escaped_url}&format=raw&include_fragment=true"
    end
    logger.info("***  calling wringer with: #{_base_url + path} ")
    return _base_url + path
  end



  def status_checker (scraped_data, property)
    if property.value_datatype == "xsd:anyURI"
      #check for 2 items in list
      scraped_data.count == 3 ? status = "initial" : status = "missing"
    else
      !scraped_data.blank? ? status = "initial" : status = "missing"
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
      scraped_data.each do |t|
        data << search_for_uri(t,property,webpage)
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

  def search_for_uri name, property, webpage
    #search for name in statments.where(website, class)
    uris = [name]

    #use property label to determine class
    expected_class = property.expected_class
    uris << expected_class

    #search condensor database
    statements = Statement.where(cache: name)
    statements.each do |s|
      uris << [name,s.webpage.rdf_uri] if (s.webpage.rdfs_class.name == expected_class)
      ## ????also check (s.webpage.website == webpage.website)
    end

    #search Culture Creates KG
    search_cckg(name, expected_class).each do |uri|
      uris << [name,uri]
    end

    return uris
  end



  def search_cckg str, rdfs_class
    q = "PREFIX schema: <http://schema.org/>            \
        select DISTINCT ?uri ?name where {              \
	          ?uri a schema:#{rdfs_class} .                \
            ?uri schema:name ?name .                    \
            filter (!EXISTS {filter (isBlank(?uri)) })  \
        } limit 100 "
    result = cc_kg_query(q, rdfs_class)
    hits = []
    result.each do |hit|
      hits << hit["uri"]["value"] if hit["name"]["value"] == str
    end
    return hits
  end


  def ISO_duration(duration_str)
    begin
      duration_seconds = "PT#{ChronicDuration.parse(duration_str)}S"
    rescue
      duration_seconds = "Bad duration: #{time}"
    end
    return duration_seconds
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
