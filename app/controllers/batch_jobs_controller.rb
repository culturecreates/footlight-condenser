# frozen_string_literal: true

# Used to call webhooks on culture-huginn.herokuapp.com
class BatchJobsController < ApplicationController
  RDF_CLASS_LABEL = 'RDF Class'
  URI_LIST_LABEL = 'URI List'
  WEBPAGE_URL_LIST_LABEL = 'Webpage URL List'

  def add_webpages
    # GET /batch_jobs/add_webpages?rdf_uri=
    # GET /batch_jobs/add_webpages.json?rdf_uri=
    params[:only_statements_with_cache_changed]

    webpages = Webpage.where(rdf_uri: params[:rdf_uri])

    rdfs_class = ''
    rdf_uris = []
    urls = []
    language = webpages.first.language
    seedurl = webpages.first.website['seedurl']

    # collect the data to send to the batch job
    webpages.each do |webpage|
      statements = Statement
                   .where(webpage_id: webpage)
                   .includes(source: [:property])

      rdf_class_statement = statements.select { |s| s.source.property.label == RDF_CLASS_LABEL }.first
      uri_statement = statements.select { |s| s.source.property.label == URI_LIST_LABEL }.first
      webpage_url_statement = statements.select { |s| s.source.property.label == WEBPAGE_URL_LIST_LABEL }.first

      # check if the webpage's statements changed
      if params.key?(:only_statements_with_cache_changed)
        cache_changed_flag = false
        if webpage_url_statement.cache_changed.present?
          if webpage_url_statement.cache_changed + 1.minute > webpage_url_statement.cache_refreshed
            cache_changed_flag = true
          end
        end
        next unless cache_changed_flag
      end

      rdfs_class = rdf_class_statement['cache']
      rdf_uris += JSON.parse(uri_statement['cache'])
      urls += JSON.parse(webpage_url_statement['cache'])
    end

    # create the array to send to the batch job
    webpages = []
    urls.each_with_index do |url, index|
      webpages << {
        url: url,
        rdf_uri: rdf_uris[index],
        language: language,
        rdfs_class: rdfs_class,
        seedurl: seedurl
      }
    end

    # call a webhook on Huginn to add new webpages to a website
    if webpages.count.positive?
      result = helpers.huginn_webhook 'webpages', webpages, 249
      respond_to do |format|
        format.html { redirect_to lists_path(seedurl: seedurl), notice: "Created batch job for #{urls.count} webpages... response: #{result} " }
        format.json { render json: { message: "Created batch job for #{urls.count} webpages... response: #{result} " }.to_json }
      end
    else
      respond_to do |format|
        format.html { redirect_to lists_path(seedurl: seedurl), notice: 'Nothing to update.' }
        format.json { render json: { message: 'Nothing to update.' }.to_json }
      end
    end
  end

  # GET /batch_jobs/refresh_webpages?seedurl=
  # Refresh all webpages of website seedurl
  def refresh_webpages
    website = Website.where(seedurl: params[:seedurl]).first
    webpages = website.webpages

   
    webpages.each do |wp|
      RefreshWebpageJob.perform_later(wp.url)
    end
  
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
