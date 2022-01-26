# Clean up database records that are old to make space.
class ExportToArtsdataJob < ApplicationJob
  queue_as :default
  def perform(seedurl, root_url)
    result = ExportGraphToDatabus.export_events(seedurl, root_url)
    Rails.logger.info("Artsdata Export #{seedurl} Result: #{result.inspect}")
  end
end