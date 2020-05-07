# Ruby code to extract data for websites into JSON for analysis by AI
require 'httparty'

seedurl = ARGV[0] || 'theplayhouse-ca'
target_language = ARGV[1] || 'en'
condenser_url = "https://footlight-condenser.herokuapp.com" ## "http://localhost:3000"

wringer_url = "http://footlight-wringer.herokuapp.com"

result = {}

webpages = HTTParty.get("#{condenser_url}/webpages.json?seedurl=#{seedurl}&per_page=1000")
sources = HTTParty.get("#{condenser_url}/sources.json?seedurl=#{seedurl}")

if target_language == "en"
    title_prefix = "title_en"
    dates_prefix = "dates"
    location_prefix = "location"
elsif target_language == "fr"
    title_prefix = "title_fr"
    dates_prefix = "dates_fr"
    location_prefix = "location_fr"
end


webpages.each do |page|
    if page["publishable"] == "Yes" && page["rdfs_class_id"] == 1 &&  page["language"] == target_language
        puts "processing page #{page["url"]}"

        #get page html
        escaped_url = CGI.escape(page["url"])
        path = "/websites/wring?uri=#{escaped_url}&format=raw&include_fragment=true"
        html = HTTParty.get("#{wringer_url}#{path}")
        input = {url: page["url"], html: html, language:page["language"]}

        #get page title, dates, performers, place
        uri = page["rdf_uri"]
        statements = HTTParty.get("#{condenser_url}/resources/#{uri}.json")

        get_algorithm = ->(property) { sources.detect{ |a| a["id"] == statements["statements"][property]["source_id"].to_i}["algorithm_value"] }


        dates = {
            value: statements["statements"][dates_prefix]["value"],
            algorithm: get_algorithm.call(dates_prefix)
        }
        if statements["statements"]["performed_by"]
            performed_by =  {
                value: statements["statements"]["performed_by"]["value"], 
                algorithm: get_algorithm.call("performed_by")
            }
        end
        location =  {
            value:statements["statements"][location_prefix]["value"], 
            algorithm: get_algorithm.call(location_prefix)
        }
        title =  {
            value:statements["statements"][title_prefix]["value"], 
            algorithm: get_algorithm.call(title_prefix)
        }
      
        output = {performed_by: performed_by, location: location, dates:dates, title: title}
        result[page["id"]] = {input: input, output: output}
    end
end

File.open("dump_#{seedurl}.json","w") do |f|
    f.write(result.to_json)
end

  puts "done writing #{result.count} objects by loading #{webpages.count} webpages"

