namespace :footlight do
  desc "This task is called by the Heroku scheduler add-on"
  task :refresh_websites => :environment do
    ExportGraphToDatabus.check_schedule(
      ENV.fetch("ARTSDATA_CALLBACK_BASE_URL", "https://footlight-condenser.herokuapp.com")
    )
  end
end
