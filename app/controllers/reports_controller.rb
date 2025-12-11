class ReportsController < ApplicationController

    def source
        # GET /reports/source.json?source_id=
        params[:startDate]  # "2018-01-01"
        params[:endDate]   # "2021-01-01"
    
        start_date = Time.zone.now
        end_date = Time.zone.now.next_year + 6.months
    
        if params[:startDate] 
          begin
            start_date = Date.parse(params[:startDate])
          rescue => exception
            logger.error("Invalid start_date parameter: #{exception.inspect}")
          end
        end
    
        if params[:endDate] 
          begin
            end_date = Date.parse(params[:endDate])
          rescue => exception
            logger.error("Invalid end_date parameter: #{exception.inspect}")
          end
        end
    
        time_span = [start_date..end_date]

        source = Source.where(id: params[:source_id]).first


        @statements = get_statements_by_source(source, time_span)

        @page_title = "Report for #{source.property.label} (source #{source.id})"

        #get Titles of events
        title_property = Property.where(label: "Title")
        title_source = Source.joins(:property).where(property: title_property, website: source.website, selected: true)
   
        @event_titles = get_statements_by_source(title_source)

        @filtered_event_titles = {}
        @statements.each do |statement|
            title = @event_titles.select{ |t| t["webpage_id"] == statement["webpage_id"] }.first
            if title
                @filtered_event_titles[statement["webpage_id"]] = title.cache
            end
        end

        @webpages = get_webpages(source.website.seedurl)
        @filtered_archive_dates = {}
        @filtered_event_uris = {}
        @statements.each do |statement|
            webpage = @webpages.select{ |t| t.id == statement["webpage_id"] }.first
            if webpage
                @filtered_archive_dates[statement["webpage_id"]] = webpage.archive_date
                @filtered_event_uris[statement["webpage_id"]] = webpage.rdf_uri
            end
        end

   end

   private

   def get_statements_by_source source, archive_date_range = [Time.zone.now - 10.years..Time.zone.now + 10.years]
        return Statement.joins({source: [:property, :website]},:webpage).where(source_id: source, sources: {webpages: {archive_date: archive_date_range} }).order(:cache)
   end

   def get_webpages seedurl
        return Webpage.joins(:website).where(rdfs_class: 1, websites: {seedurl: seedurl})
   end
   
end
