# Refresh Webpages
class RefreshWebpageJob < ApplicationJob
  queue_as :default
  def perform(url)
    webpages = Webpage.includes(:website).where(url: url)
    webpages.each do |webpage|
      StatementsController.new.refresh_webpage_statements(webpage, webpage.website.default_language, :force_scrape_every_hrs => 23)
    end
  end
end