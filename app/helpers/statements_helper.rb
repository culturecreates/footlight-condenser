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
            html = agent.get_file  use_wringer(a.delete_prefix("url="), source.render_js)
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
          end
        end
      rescue => e
        puts "Error in scrape: #{e.inspect}"
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
    if property.value_datatype == "xsd:date"
      scraped_data.each do |d|
        data << ISO_date(d)
      end
    elsif property.value_datatype == "xsd:dateTime"
      scraped_data.each do |t|
        data << ISO_dateTime(t)
      end
    elsif property.value_datatype == "xsd:time"
      scraped_data.each do |t|
        data << ISO_time(t)
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
      uris << [name,s.webpage.rdf_uri] if (s.webpage.website == webpage.website) && (s.webpage.rdfs_class.name == expected_class)
    end

    #search Culture Creates KG
    search_cckg(name, expected_class).each do |uri|
      uris << [name,uri]
    end

    return uris
  end



  def search_cckg str, rdfs_class

    @cckg_cache = {} if !defined? @cckg_cache

    q = "PREFIX schema: <http://schema.org/>            \
        select DISTINCT ?uri ?name where {              \
	          ?uri a schema:#{rdfs_class} .                \
            ?uri schema:name ?name .                    \
            filter (!EXISTS {filter (isBlank(?uri)) })  \
        } limit 100 "


    if !@cckg_cache[rdfs_class]
      data = HTTParty.post("http://rdf.ontotext.com/4045483734/cc/repositories/webPages",
        body: {'query' => q},
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded',
                  'Accept' => 'application/json',
                  'Authorization' => 'Basic czRkYWxsZGdnaDgxOjUwZjVnMXQ3OTI4OXFqdg=='} )

      if data.response.code[0] == '2'
        result = JSON.parse(data.body)["results"]["bindings"]
        @cckg_cache[rdfs_class] = result
      else
        return  {error: data.response}
      end
    else
      result = @cckg_cache[rdfs_class]
    end

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


  def ISO_time(time)
    begin
      d = Time.parse time
      iso_date =  d.strftime('%T')
    rescue
      iso_date = "Bad input time: #{time}"
    end
    return iso_date
  end

  def ISO_date(date)
  #  SAMEDI 29 JUILLET 2017, 20 H | GRAND CHAPITEAU
  # --> output "2017-08-29 20:00:00"
  # swap Juillet for July, Aout for August
    date.downcase!
    date.gsub!('juillet','July')
    date.gsub!('août', 'August')
    begin
      d = Time.parse date
      #iso_date =  d.strftime('%F %T')
      iso_date =  d.strftime('%F')
    rescue
      iso_date = "Bad input date: #{date}"
    end
    return iso_date
  end

  def ISO_dateTime(date_time)
    begin
      d = Time.parse(date_time).in_time_zone('Eastern Time (US & Canada)')
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
