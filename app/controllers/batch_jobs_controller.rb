# frozen_string_literal: true

# Used to call webhooks on culture-huginn.herokuapp.com
class BatchJobsController < ApplicationController



  def check_for_new_event_pages
    params[:seedurl]
    params[:force_scrape_every_hrs] ||= "23"
    # Get resource_list URIs
    resource_list_webpages = Webpage.includes(:website).where(websites: { seedurl: params[:seedurl] }, rdfs_class_id: RdfClass.where(name: "ResourceList"))
    # Refresh the statements for each resource_list Webpages
   
    resource_list_webpages.each do |webpage|
      RefreshWebpageJob.perform_later(wp.url, "resource_list")
    end
  end

  # GET /batch_jobs/add_webpages?rdf_uri=
  # GET /batch_jobs/add_webpages.json?rdf_uri=
  def add_webpages
    params[:rdf_uri]
    webpages = Webpage.where(rdf_uri: params[:rdf_uri])
    webpages.each do |webpage|
      puts "starting job..."
      AddWebpagesJob.perform_later(webpage.url)
    end
    respond_to do |format|
      format.html { redirect_to lists_path(seedurl: @seedurl), notice: "Created batch job to add new event webpages" }
      format.json { render json: { message: "Created batch job to add new event webpages" }.to_json }
    end
  end

  # GET /batch_jobs/refresh_webpages?seedurl=
  # Refresh all webpages of website seedurl
  def refresh_webpages
    website = Website.where(seedurl: params[:seedurl]).first
    webpages = website.webpages

   
   # webpages do |wp|
      RefreshWebpageJob.perform_later(webpages.first.url)
    #end
  
    redirect_to website_path(website), notice: "Created batch jobs for #{webpages.count} webpages. "
  end

  # GET /batch_jobs/refresh_webpages?seedurl=
  # Refresh only upcoming event
  def refresh_upcoming_events
    
    # TODO: get list of upcoming Event URIs for seedurl
    
    webpages.each do |wp|
      RefreshWebpageJob.perform_later(wp.url)
    end
  
    redirect_to website_path(website), notice: "Created batch jobs for #{urls.count} webpages. "
  end
end
