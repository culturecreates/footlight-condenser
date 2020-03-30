class ReportsController < ApplicationController

    def source
        # GET /report/source.json?source_id=
        @data = get_label_data params[:source_id]
        source = Source.where(id: params[:source_id]).first
        @title = "Report for #{source.property.label} (source #{source.id})"

        #get Titles of events
        @title_property = Property.where(label: "Title").first 
        title_source_id = Source.joins(:property).where(property: @title_property, website: source.website).first.id 

        @event_titles = get_title_data(title_source_id).to_h
        @data_for_json = {}
        @data.each do |i|
            @data_for_json[i[0]] = {title: @event_titles[i[0]], cache:i[1], status: i[2]}
        end

   end

   private

   def get_label_data source_id
       return Statement.joins({source: [:property, :website]},:webpage).where(source_id: source_id).order(:cache).pluck(:rdf_uri, :cache, :status)
   end

    def get_title_data source_id
        return Statement.joins({source: [:property, :website]},:webpage).where(source_id: source_id).order(:cache).pluck(:rdf_uri, :cache)
    end


end
