# Refresh Webpages
class RefreshWebpageJob < ApplicationJob
  queue_as :default
  include CcWringerHelper

  after_perform do |job|
    if job.arguments.last == "resource_list"
      # Use the resource_list to add new webpages
      AddWebpagesJob.perform_later(job.arguments.first)
    end
  end

  def perform(url, options = nil)
    webpages = Webpage.includes(:website).where(url: url)
    webpages.each do |webpage|
      Statements::RefreshWebpageStatementsService.new(refresh_helper: ApplicationController.helpers).call(
        webpage: webpage,
        default_language: webpage.website.default_language,
        scrape_options: { force_scrape_every_hrs: 1 }
      )
      # if after refresh the webpage is still 404 then delete it
      if wringer_received_404?(url)
        webpage.destroy
      end
    end
  end

end
