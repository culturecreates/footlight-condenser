namespace :footlight do
  desc "Removes old archived webpages and related statements"
  task :db_tidy => :environment do
    puts "running DbTidyJob in #{Rails.env}"
    DbTidyJob.perform_now
  end
end