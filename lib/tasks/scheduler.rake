desc "This task is called by the Heroku scheduler add-on"
task :refresh_websites => :environment do
  puts "Refreshing websites..."
  ExportGraphToDatabus.check_schedule('http://localhost:3000')
  puts "Done refreshing websites."
end