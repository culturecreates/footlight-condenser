require 'httparty'

seedurl = ARGV[0] || 'theplayhouse-ca'

result = {}

webpages = HTTParty.get("https://footlight-condenser.herokuapp.com/webpages.json?seedurl=#{seedurl}")
sources = HTTParty.get("http://localhost:3000/sources.json?seedurl=#{seedurl}")



webpages.each do |page|
    if page["publishable"] == "Yes" && page["rdfs_class_id"] == 1 &&  page["language"] == "en"
       
        #get page html
        escaped_url = CGI.escape(page["url"])
        path = "/websites/wring?uri=#{escaped_url}&format=raw&include_fragment=true"
        html = HTTParty.get("http://footlight-wringer.herokuapp.com#{path}")
        input = {url: page["url"], html: html, language:page["language"]}

        #get page title, dates, performers, place
        uri = page["rdf_uri"]
        statements = HTTParty.get("https://footlight-condenser.herokuapp.com/resources/#{uri}.json")

        get_algorithm = ->(y) { sources.detect{ |a| a["id"] == statements["statements"][y]["source_id"].to_i}["algorithm_value"] }

        dates = {
            value: statements["statements"]["dates"]["value"],
            algorithm: get_algorithm.call("dates")
        }
        performed_by =  {
            value: statements["statements"]["performed_by"]["value"], 
            algorithm: get_algorithm.call("performed_by")
        }
        location =  {
            value:statements["statements"]["location"]["value"], 
            algorithm: get_algorithm.call("location")
        }
        title_en =  {
            value:statements["statements"]["title_en"]["value"], 
            algorithm: get_algorithm.call("title_en")
        }
        
        output = {performed_by: performed_by, location: location, dates:dates, title_en: title_en}
        result[page["id"]] = {input: input, output: output}
    end
end

File.open("dump_#{seedurl}.json","w") do |f|
    f.write(result.to_json)
end

  puts "done writing #{result.count} objects"

