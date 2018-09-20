class EventsController < ApplicationController

  # GET /websites/:seedurl/events
  def index
    @events = helpers.get_uris params[:seedurl], "Event"
    @events.each do |event|

      _statements = []
      _webpages = Webpage.where(rdf_uri: event[:rdf_uri])
      _webpages.each do |webpage|
        webpage.statements.each do |statement|
          _statements << statement
        end
      end


      if !_statements.blank?
        event[:statements_status] = helpers.calculate_resource_status _statements
        _statements.each do |s|
           if s.source.property.label == "Title"  && s.source.selected
             event[:title] = s.cache if s.source.language == "en"
             event[:title] = s.cache if s.source.language == "fr" && event[:title].blank?
          end
          event[:photo] = s.cache if s.source.property.label == "Photo" && s.source.selected
        end
      end
    end
  end




end
