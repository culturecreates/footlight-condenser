class ExportArtifactJob < ApplicationJob
  queue_as :default

  def perform(*args)
    website = args[:seedurl] 
    event_controller = EventsController.new
    all_events = event_controller.website_statements_by_event(website)

    publishable = []
    all_events.each do |e|
      publishable << e[0] if event_controller.event_publishable?(e[1])
    end

    artifact = JsonldGenerator.dump_events(publishable)

 

    # POST /databus?jsonld=&artifact=&version=
    # databus = DatabusController.new
    # databus.save_on_s3(jsonld: @dump, artifact: "test artifact", version: "2021-02-23", file: "test1.json")
    # redirect_to databus_index_path
  end
end
