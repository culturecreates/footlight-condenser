class PlacesController < ApplicationController

    def index
        # GET /places.json?seedurl=
        @places = get_places
        @places.each_with_index do |place,index|
            begin
                @places[index] = [place[0],JSON.parse(place[1])]
            rescue => exception
                if place[1].class == Array 
                     @places[index] = [place[0],[[place[1].join(", ")]]] 
                else  
                    @places[index] = [place[0],[place[1]]]
                end 
            end
        end
        
        
    end


private

    def get_places 
        return Statement.joins({source: [:property, :website]},:webpage).where({sources:{selected: true, properties:{label: "Location", rdfs_class: 1}, websites:  {seedurl: params[:seedurl]} }  }  ).pluck(:rdf_uri, :cache, "sources.language", :url)
    end

end
