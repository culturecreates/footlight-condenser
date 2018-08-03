module StatementsHelper

  def scrape(source, url)
    algorithm = source.algorithm_value
    if algorithm.start_with?("manual=")
      results_list = [algorithm.delete_prefix("manual=")]
    else
      begin
        agent = Mechanize.new
        agent.user_agent_alias = 'Mac Safari'
        html = agent.get_file  use_wringer(url, source.render_js)
        page = Nokogiri::HTML html
        results_list = []
        algorithm.split(',').each do |a|
          if a.start_with? 'url'
            #replace current page by sraping new url
            html = agent.get_file  use_wringer(a.delete_prefix("url="), source.render_js)
            page = Nokogiri::HTML html
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



  def format_datatype (scraped_data, property, webpage)
    data = []
    if property.value_datatype == "xsd:date"
      scraped_data.each do |d|
        data << ISO_date(d)
      end
    elsif property.value_datatype == "xsd:time"
      scraped_data.each do |t|
        data << ISO_time(t)
      end
    elsif property.value_datatype == "xsd:anyURI"
      scraped_data.each do |t|
        data << search_for_uri(t,property,webpage)
      end
    else
      data = scraped_data
    end
    data = data.first if data.count == 1
    return data
  end

  def search_for_uri name, property, webpage
    #search for name in statments.where(website, class)
    uris = [name]
    statements = Statement.where(cache: name)
    #use property label to determine class
    expected_class = property.expected_class
    statements.each do |s|
      uris << s.webpage.rdf_uri if (s.webpage.website == webpage.website) && (s.webpage.rdfs_class.name == expected_class)
    end
    return uris
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

  def format_language language
    "@" + language if !language.blank?
  end

  def build_key statement # for JSON output
      new_key = statement.source.property.label.downcase.sub(" ","_")
      new_key = "#{new_key}_#{statement.source.language}" if !statement.source.language.blank?
      return new_key
  end

end
