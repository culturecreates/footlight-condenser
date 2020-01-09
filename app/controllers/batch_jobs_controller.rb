class BatchJobsController < ApplicationController
    RDF_CLASS_LABEL = "RDF Class"
    URI_LIST_LABEL = "URI List"
    WEBPAGE_URL_LIST_LABEL = "Webpage URL List"

    def add_webpages 
        # GET /batch_jobs/add_webpages?rdf_uri=

        webpage = Webpage.where(rdf_uri:params[:rdf_uri])
        statements = Statement.where(webpage_id: webpage)

        #collect the data to send to the batch job
        rdfs_class = ""
        rdf_uris = ""
        urls = ""
        language = webpage[0].language
        seedurl = webpage[0].website["seedurl"]
        statements.each do |s|
            data_label = s.source.property.label
            if data_label == RDF_CLASS_LABEL
                rdfs_class = s["cache"]
            elsif  data_label == URI_LIST_LABEL
                rdf_uris = JSON.parse(s["cache"])
            elsif  data_label == WEBPAGE_URL_LIST_LABEL
                urls = JSON.parse(s["cache"])
            end
        end
      
        #create the array to send to the batch job
        webpages = []
        urls.each_with_index do |url,index|
            webpages << {
                url: url, 
                rdf_uri: rdf_uris[index],
                language: language, 
                rdfs_class: rdfs_class, 
                seedurl: seedurl}
        end

        #call batch processor with array of webpages json
        result = helpers.huginn_webhook  "webpages", webpages, 249

        redirect_to lists_path(seedurl: seedurl), notice: "Creating batch job for #{urls.count} webpages... response: #{result} " 

    end


    def refresh_webpages
        # GET /batch_jobs/refresh_webpages?seedurl=

        website = Website.where(seedurl: params[:seedurl]).first
        webpages = website.webpages

        urls = []
        webpages.each do |wp|
            urls << {url: wp.url}
        end
        puts urls

        result = helpers.huginn_webhook  "urls", urls, 250
        redirect_to website_path(website), notice: "Creating batch job for #{urls.count} webpages... response: #{result} " 
    end
end
