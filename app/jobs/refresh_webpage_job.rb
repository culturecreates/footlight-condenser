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
      Distillator::RefreshRunner.call(
        webpage: webpage,
        refresh_helper: ApplicationController.helpers,
        scrape_options: extract_scrape_options(options)
      )

      removal_candidate = Distillator::WebpageRemovalCandidate.call(
        webpage,
        include_fragment: extract_scrape_options(options)[:include_fragment]
      )
      if removal_candidate.delete?
        webpage.destroy
      end
    end
  end
  
  private

  def extract_scrape_options(options)
    return {} if options.blank? || options == "resource_list"
    return options.symbolize_keys if options.respond_to?(:symbolize_keys)

    {}
  end
end
