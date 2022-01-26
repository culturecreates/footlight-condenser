class ExportGraphToDatabus
  def self.export_events(seedurl, root_url)
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

    report_callback_url = "#{root_url}/messages/webhook.json?artifact=#{artifact}"

    # Save to S3
    result = save_on_s3(jsonld: dump, artifact: artifact, version: version, file: file)
    puts "Result of save_on_s3: #{result.inspect}"

    if result # TODO: check for S3 errors
      # Add to Artsdata Databus
      result = add_to_databus(group: group, artifact: artifact, download_url: download_url, download_file: file, version: version, report_callback_url: report_callback_url)
      puts "Result of add_to_databus: #{result.inspect}"
    end

    result
  end

  ##
  # Check the schedule for each website and refresh export if needed.
  # Call this method every hour with a cron job.
  # INPUT: root_url = root url for callback mechanism to get reports
  # For each website use:
  #    website.last_refresh = dateTime of last refresh
  #    website.schedule_time = time of day to refresh
  #    website.schedule_every_days = days to wait before refresh
  def self.check_schedule(root_url)
    websites = Website.all
    websites.each do |website|
      # ensure there is a schedule
      next unless schedule_every_days = website.schedule_every_days 
      next unless schedule_every_days.to_i > 0

      # ensure that website has been crawled atleast once
      next unless last_refresh = website.last_refresh

      # ensure that the number of days has passed
      days_past = Time.now.at_beginning_of_day - last_refresh.at_beginning_of_day
      next unless days_past >= schedule_every_days.days
         
      # ensure that the scheduled time of day has passed
      next unless Time.now.utc.strftime( "%H%M" ) >= website.schedule_time.utc.strftime( "%H%M" )
            
      # refresh webpages
      BatchJobsController.new.refresh_upcoming_events_jobs(website.seedurl)
      BatchJobsController.new.check_for_new_webpages_jobs(website.seedurl)
      ExportToArtsdataJob.set(wait: 20.minutes).perform_later
      website.last_refresh = Time.now
      website.save
    end
  end

  # Save a JSON-LD on S3
  def self.save_on_s3(jsonld:, artifact:, version:, file:)
    bucket = "data.culturecreates.com"

    begin
      client = Aws::S3::Client.new(
        region: "ca-central-1", 
        access_key_id: ENV["ACCESS_KEY_ID"], 
        secret_access_key: ENV["SECRET_ACCESS_KEY"]
      )

      client.put_object(
        bucket: bucket,
        key: "databus/culture-creates/footlight/#{artifact}/#{version}/#{file}", 
        body: jsonld,
        cache_control: 'max-age=0'
      )
    rescue Aws::Sigv4::Errors::MissingCredentialsError => credentials_error
      credentials_error
    end
  end

  def self.add_to_databus(group:, artifact:, download_url:, download_file:, version:, report_callback_url:, shacl_file: 'condenser')
    publisher = 'https://graph.culturecreates.com/id/footlight'

    HTTParty.post(artsdata_databus_api_url,
      query: {
        publisher: publisher,
        group: group,
        artifact: artifact,
        version: version,
        downloadUrl: download_url,
        downloadFile: download_file,
        reportCallbackUrl: report_callback_url,
        shacl: shacl_file
      } 
    )
  end

  def self.artsdata_databus_api_url
    if Rails.env.development?  || Rails.env.test?
      "http://localhost:#{ARTSDATA_API_PORT}/databus"
    else
      'http://api.artsdata.ca/databus'
    end
  end
end
