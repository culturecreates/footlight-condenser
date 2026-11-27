# frozen_string_literal: true

# Used to call webhooks on culture-huginn.herokuapp.com
class BatchJobsController < ApplicationController

  def check_for_new_webpages
    check_for_new_webpages_jobs(params[:seedurl])
    respond_to do |format|
      format.html { redirect_to lists_path(seedurl:params[:seedurl]), notice: "Created batch jobs to refresh resource lists and add new webpages for #{ params[:seedurl]}" }
      format.json { render json: { message: "Created batch jobs to refresh resource lists and add new webpages for #{ params[:seedurl]}" }.to_json }
    end
  end

  # GET /batch_jobs/add_webpages?rdf_uri=
  # GET /batch_jobs/add_webpages.json?rdf_uri=
  def add_webpages
    params[:rdf_uri]
    webpages = Webpage.where(rdf_uri: params[:rdf_uri])
    webpages.each do |webpage|
      AddWebpagesJob.perform_later(webpage.id) # This job calls RefreshWebpageJob on new webpages added.
    end
    respond_to do |format|
      format.html { redirect_to lists_path(seedurl: @seedurl), notice: "Created batch jobs to add webpages from #{ params[:rdf_uri]}" }
      format.json { render json: { message: "Created batch job to add new event webpages" }.to_json }
    end
  end

  # GET /batch_jobs/refresh_webpages?seedurl=
  # Refresh all webpages of website seedurl past and upcoming
  def refresh_webpages
    website = Website.where(seedurl: params[:seedurl]).first
    webpages = website.webpages
    webpages.each do |wp|
      RefreshWebpageJob.perform_later(wp.url)
    end
    redirect_to website_path(website), notice: "Created batch jobs for #{webpages.count} webpages. "
  end

  # GET /batch_jobs/refresh_upcoming_events?seedurl=
  # Refresh only upcoming event
  def refresh_upcoming_events
    website = Website.where(seedurl: params[:seedurl]).first
    webpage_count = refresh_upcoming_events_jobs(params[:seedurl])
    redirect_to website_path(website), notice: "Created batch jobs for #{webpage_count} webpages with upcoming events. "
  end

  ####################


  def check_for_new_webpages_jobs(seedurl, scheduled: false)
    website_ids = Website.where(seedurl: seedurl).select(:id)
    resource_list_webpages = Distillator::TransitionEventInventory.list_pages(website_ids)
    resource_list_webpages = resource_list_webpages.includes(:website, :discovery_target_website) if scheduled
    # Refresh the statements for each resource_list Webpages
    resource_list_webpages.each do |wp|
      if scheduled && Monitoring::ResourceListRefresh.target_for(wp).monitorable?
        scheduled_at = Time.current.floor(6)
        Monitoring::ResourceListRefresh.scheduled(wp, at: scheduled_at)
        RefreshWebpageJob.perform_later(wp.id, "resource_list", scheduled_at.iso8601(6))
      else
        RefreshWebpageJob.perform_later(wp.id, "resource_list")
      end
    end
  end

  # Used by refresh_upcoming_events and ExportGraphToDatabus
  def refresh_upcoming_events_jobs(seedurl)
    event_class = RdfsClass.where(name: "Event").first
    start_date = Time.zone.now
    end_date = start_date + 5.years
    webpages = Webpage.includes(:website).where(websites: { seedurl: seedurl }, rdfs_class: event_class, archive_date: [start_date..end_date])
    webpages.each do |wp|
      RefreshWebpageJob.perform_later(wp.url)
    end
    return webpages.count
  end
end
