class ExportGraphToDatabus

  def self.export(seedurl)
    # Create Graph
    event_controller = EventsController.new
    publishable = event_controller.publishable_events(seedurl)
    dump = JsonldGenerator.dump_events(publishable)

    # Databus variables
    helpers = ApplicationController.helpers
    file = helpers.make_databus_file(seedurl)
    artifact = helpers.make_databus_artifact(seedurl)
    group = helpers.make_databus_group
    version = helpers.make_databus_version
    download_url = helpers.make_databus_download_url(seedurl,version)

    # Save to S3
    databus = DatabusController.new
    result = databus.save_on_s3(jsonld: dump, artifact: artifact, version: version, file: file)

    if result # TODO: check for S3 errors
      # Add to Artsdata Databus
      result = databus.add_to_databus(group: group, artifact: artifact, download_url: download_url, download_file: file, version: version)
    end

    result
  end

  def self.check_schedule
    # get list of websites
    websites = Website.all

    # check which websites need to be refreshed
    websites.each do |website|
      schedule_every_days = website.schedule_every_days
      schedule_time = website.schedule_time # only hour of day
      last_refresh = website.last_refresh

      if last_refresh && schedule_every_days
        if schedule_every_days.to_i > 0
          days_past = Time.now.at_beginning_of_day - last_refresh.at_beginning_of_day
          if days_past >= schedule_every_days.days
            if Time.now.utc.strftime( "%H%M" ) >= schedule_time.utc.strftime( "%H%M" )
              # queue websites to refresh and set refresh_date
              logger.info("Artsdata Export #{website.inspect}")
              result = export(website.seedurl)
              logger.info("Artsdata Export Result: #{result.inspect}")
              website.last_refresh = Time.now
              website.save
            end
          end
        end
      end
    end
   end
end
