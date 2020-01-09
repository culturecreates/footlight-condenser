class ListsController < ApplicationController

    def index
        # GET /lists.json?seedurl=
   
        @uris = helpers.get_uris params[:seedurl], "ResourceList"
    end


   
end
