class ReportsController < ApplicationController

    def source
        # GET /report/label.json?source_id=
        @data = get_label_data params[:source_id]
        source = Source.where(id: params[:source_id]).first
        @title = "Report for #{source.property.label} (source #{source.id})"
   end

   private

   def get_label_data source_id
       return Statement.joins({source: [:property, :website]},:webpage).where(source_id: source_id).pluck(:rdf_uri, :cache)
   end
end
