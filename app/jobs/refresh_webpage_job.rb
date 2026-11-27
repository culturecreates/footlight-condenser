# Refresh Webpages
class RefreshWebpageJob < ApplicationJob
  queue_as :default

  after_perform do |job|
    if job.arguments[1] == "resource_list"
      if @resource_list_observation
        AddWebpagesJob.perform_later(job.arguments.first, monitoring_observation: @resource_list_observation)
      else
        AddWebpagesJob.perform_later(job.arguments.first)
      end
    end
  end

  def perform(webpage_id_or_url, options = nil, schedule_stamp = nil)
    scope = Webpage.includes(:website)
    webpages = webpage_id_or_url.is_a?(Integer) ? scope.where(id: webpage_id_or_url) : scope.where(url: webpage_id_or_url)
    scheduled_at = Time.iso8601(schedule_stamp) if schedule_stamp
    webpages.each do |webpage|
      started_at = Time.current.floor(6)
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
      elsif scheduled_at
        @resource_list_observation = Monitoring::ResourceListRefresh.refreshed(webpage, scheduled_at: scheduled_at, started_at: started_at)
      end
    rescue StandardError => error
      Monitoring::ResourceListRefresh.failed(webpage, scheduled_at: scheduled_at, phase: :refresh, error: error) if scheduled_at
      raise
    end
  end
  
  private

  def extract_scrape_options(options)
    return {} if options.blank? || options == "resource_list"
    return options.symbolize_keys if options.respond_to?(:symbolize_keys)

    {}
  end
end
