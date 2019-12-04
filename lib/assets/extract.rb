require 'httparty'

webpages = HTTParty.get('https://footlight-condenser.herokuapp.com/webpages.json?seedurl=theplayhouse-ca')



# {"id"=>2936, "url"=>"http://esplanade.ca/theatres/theatres-current-upcoming-theatres/2019/12/mother-theresa-school-christmas-concert-2019/", "language"=>"en", "rdf_uri"=>"adr:esplanade-ca_mother-theresa-school-christmas-concert-2019", "rdfs_class_id"=>1, "archive_date"=>"0001-12-17T18:59:58.000-04:56", "website_id"=>91, "created_at"=>"2019-12-03T04:08:19.825-05:00", "updated_at"=>"2019-12-03T04:08:32.620-05:00", "publishable"=>"No"} 


result = {}
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
        dates = statements["statements"]["dates"]["value"]
        performed_by =  statements["statements"]["performed_by"]["value"]
        location = statements["statements"]["location"]["value"]
        title_en =  statements["statements"]["title_en"]["value"]
        output = {performed_by: performed_by, location: location, dates:dates, title_en: title_en}
        result[page["id"]] = {input: input, output: output}
    end
end

File.open("dump.json","w") do |f|
    f.write(result.to_json)
end

  puts "done writing #{result.count} objects"

