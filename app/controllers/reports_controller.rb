class ReportsController < ApplicationController

    def source
        # GET /report/source.json?source_id=
       

        source = Source.where(id: params[:source_id]).first
        @statements = get_statements_by_source(source)


        @page_title = "Report for #{source.property.label} (source #{source.id})"

        #get Titles of events
        title_property = Property.where(label: "Title").first 
        title_source = Source.joins(:property).where(property: title_property, website: source.website, selected: true).first

        @event_titles = get_statements_by_source(title_source)

        # @data_for_json = {}
        # @data.each do |i|
        #     @data_for_json[i[0]] = {title: @event_titles[i[0]], cache:i[1], status: i[2]}
        # end

   end

   private

   def get_statements_by_source source
       #return Statement.joins({source: [:property, :website]},:webpage).where(source_id: source_id).order(:cache).pluck(:rdf_uri, :cache, :status)
       return Statement.joins({source: [:property, :website]},:webpage).where(source_id: source).order(:cache)
   end

   

end

# {
#     "uri": "adr:hector-charland-com_lhomme-elephant",
#     "rdfs_class": "Event",
#     "seedurl": "hector-charland-com",
#     "archive_date": "2019-01-22T01:00:00.000Z",
#     "statements": {
#         "title_fr" :{
#             "id": 45328,
#             ...
#         },
#       "photo_fr": {
#         "alternatives": [
#           {
#             "id": 45329,
#             "status": "initial",
#           }
#         ],
#         "id": 45328,
#         "status": "ok",
#         "status_origin": "admin",
#         "cache_refreshed": "2020-01-06T14:48:50.271Z",
#         "cache_changed": null,
#         "source_id": 123,
#         "webpage_id": 315,
#         "created_at": "2020-01-06T14:48:50.299Z",
#         "updated_at": "2020-01-06T14:51:48.159Z",
#         "value": "https://hector-charland.com/wp-content/uploads/2018/04/LHomme-Elephantpng_preview.png",
#         "label": "Photo",
#         "language": "fr",
#         "source_label": null,
#         "datatype": "",
#         "expected_class": "",
#         "uri": "http://schema.org/image",
#         "manual": false
#       }
