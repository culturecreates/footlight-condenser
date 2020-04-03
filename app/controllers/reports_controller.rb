class ReportsController < ApplicationController

    def source
        # GET /report/source.json?source_id=
       

        source = Source.where(id: params[:source_id]).first
        @statements = get_statements_by_source(source)


        @page_title = "Report for #{source.property.label} (source #{source.id})"

        #get Titles of events
        title_property = Property.where(label: "Title")
        title_source = Source.joins(:property).where(property: title_property, website: source.website, selected: true)
   
        @event_titles = get_statements_by_source(title_source)
        @archive_dates = get_archive_dates(source.website.seedurl)

   end

   private

   def get_statements_by_source source
            return Statement.joins({source: [:property, :website]},:webpage).where(source_id: source).order(:cache)
   end

   def get_archive_dates seedurl
    return Webpage.joins(:website).where(rdfs_class: 1, websites: {seedurl: seedurl})
   end
   
end
