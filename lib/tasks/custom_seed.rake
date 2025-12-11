namespace :db do
  namespace :seed do
    task :single => :environment do
      filename = Dir[Rails.root.join("db", "seeds", "#{ENV['SEED']}.seeds.rb").to_s][0]
      puts "Seeding #{filename}..."
      load(filename) if File.exist?(filename)
    end

    task :base => :environment do
      filename = Dir[Rails.root.join("db/seeds/seeds.rb").to_s][0]
      puts "Seeding #{filename}..."
      load(filename) if File.exist?(filename)
    end
  end
end
