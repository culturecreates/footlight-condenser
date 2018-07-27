module StatementsHelper

  def scrape(source, url)
    begin
      algorithm = source.algorithm_value
      agent = Mechanize.new
      agent.user_agent_alias = 'Mac Safari'
      html = agent.get_file  use_wringer(url, source.render_js)
      page = Nokogiri::HTML html

      results_list = []
      algorithm.split(',').each do |a|
        page_data = page.xpath(a.delete_prefix("xpath=")) if a.include? 'xpath'
        page_data = page.css(a.delete_prefix("css="))   if a.include? 'css'
        page_data.each { |d| results_list << d.text}
      end
    rescue => e
      puts "Error in scrape: #{e.inspect}"
      results_list = ["Error scrapping"]
    end
    return results_list
  end


  def use_wringer(url, render_js)
    escaped_url = CGI.escape(url)
    _base_url = "http://footlight-wringer.herokuapp.com"
    if render_js
      path = "/websites/wring?uri=#{escaped_url}&format=raw&include_fragment=true&use_phantomjs=true"
    else
      path = "/websites/wring?uri=#{escaped_url}&format=raw&include_fragment=true"
    end
    return _base_url + path
  end


  def format_datatype (scraped_data, property)
    data = []
    if property.value_datatype == "xsd:date"
      scraped_data.each do |d|
        data << ISO_date(d)
      end
    else
      data = scraped_data
    end
    data = data.first if data.count == 1
    return data
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

end
