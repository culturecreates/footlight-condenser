module CcWringerHelper


  def get_wringer_url_per_environment
    if Rails.env.development?  || Rails.env.test?
      "http://localhost:3009"
    else
      "http://footlight-wringer.herokuapp.com"
    end
  end

  def use_wringer(url, render_js = false, options={})
    defaults = { :force_scrape_every_hrs => nil }
    options = defaults.merge(options)

    url = url.first if url.class == Array
    escaped_url = CGI.escape(url)

    if render_js
      path = "/websites/wring?uri=#{escaped_url}&format=raw&include_fragment=true&use_phantomjs=true"
    else
      path = "/websites/wring?uri=#{escaped_url}&format=raw&include_fragment=true"
    end

    if options[:force_scrape_every_hrs]
      path += "&force_scrape_every_hrs=#{options[:force_scrape_every_hrs]}"
    end

    logger.info("***  calling wringer with: #{get_wringer_url_per_environment + path} ")
    return get_wringer_url_per_environment + path
  end


  def update_jsonld_on_wringer url, graph_uri, jsonld
    # if is_publishable?(jsonld)
       #update condensed JSON-LD in wringer to update KG
       wringer_api = "/condensers/condense.json"

       data = HTTParty.patch(get_wringer_url_per_environment() + wringer_api,
         body: {'url' => url, 'graph_uri' => graph_uri, 'jsonld' => jsonld.to_json},
         headers: { 'Content-Type' => 'application/x-www-form-urlencoded',
                   'Accept' => 'application/json'} )

       if data.response.code[0] == '2'
          result = {message: "Successfully updated JSON-LD in wringer"}
       else
         result =  {error: data.response.code, message: data.response.message}
       end


    # else
    #   #delete condensed JSON-LD in wringe to delete triples in KG
    # end

  end





end
