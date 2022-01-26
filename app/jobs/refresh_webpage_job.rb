# Refresh Webpages
class RefreshWebpageJob < ApplicationJob
  queue_as :default

  after_perform do |job|
    if job.arguments.last == "resource_list"
      # Use the resource_list to add new webpages
      AddWebpagesJob.perform_later(job.arguments.first)
    end
  end

  def perform(url, options = nil)
    webpages = Webpage.includes(:website).where(url: url)
    webpages.each do |webpage|
      StatementsController.new.refresh_webpage_statements(webpage, webpage.website.default_language, { :force_scrape_every_hrs => 23 })
    end
  end
end