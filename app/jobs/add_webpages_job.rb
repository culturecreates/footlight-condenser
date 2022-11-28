# Add new Webpages based on statements for Class ResourceList
class AddWebpagesJob < ApplicationJob
  queue_as :default

  RDF_CLASS_LABEL = 'RDF Class'
  URI_LIST_LABEL = 'URI List'
  WEBPAGE_URL_LIST_LABEL = 'Webpage URL List'

  def perform(url)

    webpage = Webpage.includes(:website).where(url: url).first
    rdfs_class = ''
    rdf_uris = []
    urls = []
    language = webpage.language

    statements = Statement.where(webpage_id: webpage).includes(source: [:property])

    rdf_class_statement = statements.select { |s| s.source.property.label == RDF_CLASS_LABEL }.first
    uri_statement = statements.select { |s| s.source.property.label == URI_LIST_LABEL }.first
    webpage_url_statement = statements.select { |s| s.source.property.label == WEBPAGE_URL_LIST_LABEL }.first

    rdfs_class = rdf_class_statement['cache']
    rdf_uris += JSON.parse(uri_statement['cache'])
    urls += JSON.parse(webpage_url_statement['cache'])

    if rdf_uris.count != urls.count  # exit if list has unapped urls to uris
      logger.error("Invalid Resource list has unapped urls to uris: #{e.inspect}")
      return 
    end
    urls.each_with_index do |webpage_url, index|
      wp = Webpage.new(
        url: webpage_url,
        rdf_uri: rdf_uris[index],
        language: language,
        rdfs_class: RdfsClass.where(name: rdfs_class).first,
        website: webpage.website
      )
      if wp.save
        RefreshWebpageJob.perform_later(webpage_url)
      end
    end

  end
end