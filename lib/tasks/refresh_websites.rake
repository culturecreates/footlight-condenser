namespace :footlight do
  desc "This task is called by the Heroku scheduler add-on"
  task :refresh_websites => :environment do
    ExportGraphToDatabus.check_schedule('https://footlight-condenser.herokuapp.com') # check results from artsdata callback url on footlight in production
  end
end