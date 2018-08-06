class EventsController < ApplicationController

  # GET /websites/:seedurl/events
  def index
    @events = helpers.get_uris params[:seedurl], "Event"
    @events.each do |event|
      statements = Webpage.where(rdf_uri: event[:rdf_uri]).first.statements
      if !statements.blank?
        event[:statements_status] = helpers.calculate_resource_status statements
        statements.each do |s|
          event[:title_en] = s.cache if s.source.property.label == "Title"
          event[:photo] = s.cache if s.source.property.label == "Photo"
        end
      end
    end
  end




end
