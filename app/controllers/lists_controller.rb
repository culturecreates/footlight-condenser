class ListsController < ApplicationController

    def index
        # GET /lists.json?seedurl=
   
        @uris = helpers.get_uris params[:seedurl], "ResourceList"
    end


    def add_webpages 
        # GET /lists/add_webpages?rdf_uri=

        webpage = Webpage.where(rdf_uri:params[:rdf_uri])

        statements = Statement.where(webpage_id: webpage)


        urls = JSON.parse(statements[0]["cache"])
        rdf_uris = JSON.parse(statements[1]["cache"])
        language = webpage[0].language
        rdfs_class = statements[2]["cache"]
        seedurl = webpage[0].website["seedurl"]

        webpages = []
        urls.each_with_index do |url,index|
            webpages << {
                url: url, 
                rdf_uri: rdf_uris[index],
                language: language, 
                rdfs_class: rdfs_class, 
                seedurl: seedurl}
        end

        puts webpages
        #call Huginn with array of webpages json
        result = helpers.huginn_webhook  webpages

        redirect_to lists_path(seedurl: seedurl), notice: "Adding #{urls.count} webpages... response: #{result} " 

    end
end
