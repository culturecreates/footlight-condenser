# frozen_string_literal: true

# Used to call webhooks on culture-huginn.herokuapp.com
class BatchJobsController < ApplicationController
  RDF_CLASS_LABEL = 'RDF Class'
  URI_LIST_LABEL = 'URI List'
  WEBPAGE_URL_LIST_LABEL = 'Webpage URL List'

  def add_webpages
    # GET /batch_jobs/add_webpages?rdf_uri=
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
      redirect_to lists_path(seedurl: seedurl), notice: "Created batch job for #{urls.count} webpages... response: #{result} "
    else
      redirect_to lists_path(seedurl: seedurl), notice: 'Nothing to update '
    end
  end

  def refresh_webpages
    # GET /batch_jobs/refresh_webpages?seedurl=
    # Call a webhook on Huginn with a list of urls to refresh.

    website = Website.where(seedurl: params[:seedurl]).first
    webpages = website.webpages

    urls = []
    webpages.each do |wp|
      urls << { url: wp.url }
    end
    puts urls

    result = helpers.huginn_webhook 'urls', urls, 250
    redirect_to website_path(website), notice: "Created batch job for #{urls.count} webpages... response: #{result} "
  end
end
