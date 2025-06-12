module CcWringerHelper
  def use_wringer(url, render_js = false, options={})
    defaults = { :force_scrape_every_hrs => nil }
    options = defaults.merge(options)
    url = url.first if url.class == Array

    escaped_url = CGI.escape(url)
    path = "/websites/wring?uri=#{escaped_url}&format=raw&include_fragment=true"
    path += "&use_phantomjs=true" if render_js
    path += "&force_scrape_every_hrs=#{options[:force_scrape_every_hrs]}" if options[:force_scrape_every_hrs]
    path += "&json_post=true" if options[:json_post]
  
    logger.info("***  calling wringer with: #{get_wringer_url_per_environment() + path} ")
    return get_wringer_url_per_environment() + path
  end

  def wringer_received_404?(url)
    escaped_url = CGI.escape(url) # wringer stores the url escaped
    double_escaped_url = CGI.escape(escaped_url)
    path = "/websites.json?term=#{double_escaped_url}"
    data = HTTParty.get(get_wringer_url_per_environment() + path)
  
    webpage = data.first 
    if webpage["http_response_code"] == 404 && webpage["uri"] == escaped_url
      return true
    else
      return false
    end
  end
  

  def get_wringer_url_per_environment
    if Rails.env.development?  || Rails.env.test?
      "http://localhost:3009"
    else
      "http://footlight-wringer.herokuapp.com"
    end
  end

  # def get_wringer_url_per_environment
      # "http://footlight-wringer.herokuapp.com"
  # end

end
