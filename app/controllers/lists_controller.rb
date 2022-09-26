class ListsController < ApplicationController

    def index
        # GET /lists.json?seedurl=
   
        @resource_lists = helpers.get_uris params[:seedurl], "ResourceList"
    end


   
end
