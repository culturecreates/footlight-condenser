# Add new Webpages based on statements for Class ResourceList
class AddWebpagesJob < ApplicationJob
  queue_as :default

  RDF_CLASS_LABEL = 'RDF Class'
  URI_LIST_LABEL = 'URI List'
  WEBPAGE_URL_LIST_LABEL = 'Webpage URL List'
  InvalidResourceListError = Class.new(StandardError)

  def perform(url)
    webpage = Webpage.includes(:website).where(url: url).first
    statements = Statement.where(webpage: webpage).includes(source: [:property])
    statements_by_label = statements.index_by { |statement| statement.source.property.label }

    rdfs_class_name = statements_by_label[RDF_CLASS_LABEL]&.cache.to_s.strip
    rdf_uris = parse_json_array!(
      statements_by_label[URI_LIST_LABEL]&.cache,
      label: URI_LIST_LABEL,
      webpage: webpage
    )
    urls = parse_json_array!(
      statements_by_label[WEBPAGE_URL_LIST_LABEL]&.cache,
      label: WEBPAGE_URL_LIST_LABEL,
      webpage: webpage
    )

    validate_resource_list!(
      webpage: webpage,
      rdfs_class_name: rdfs_class_name,
      rdf_uris: rdf_uris,
      urls: urls
    )

    rdfs_class = RdfsClass.find_by!(name: rdfs_class_name)
    created_urls = []

    ActiveRecord::Base.transaction do
      urls.each_with_index do |webpage_url, index|
        next if Webpage.exists?(url: webpage_url, website: webpage.website)

        Webpage.create!(
          url: webpage_url,
          rdf_uri: rdf_uris[index],
          language: webpage.language,
          rdfs_class: rdfs_class,
          website: webpage.website
        )
        created_urls << webpage_url
      end
    end

    created_urls.each do |webpage_url|
      RefreshWebpageJob.perform_later(webpage_url)
    end
  end

  private

  def parse_json_array!(raw_value, label:, webpage:)
    parsed = JSON.parse(raw_value.to_s)
    return parsed if parsed.is_a?(Array)

    raise_invalid_resource_list!(
      webpage: webpage,
      error: "#{label} must be a JSON array",
      field: label
    )
  rescue JSON::ParserError => e
    raise_invalid_resource_list!(
      webpage: webpage,
      error: "#{label} is not valid JSON: #{e.message}",
      field: label
    )
  end

  def validate_resource_list!(webpage:, rdfs_class_name:, rdf_uris:, urls:)
    if rdfs_class_name.blank?
      raise_invalid_resource_list!(
        webpage: webpage,
        rdf_uris_count: rdf_uris.count,
        urls_count: urls.count,
        error: "#{RDF_CLASS_LABEL} is blank",
        field: RDF_CLASS_LABEL
      )
    end

    if rdf_uris.count != urls.count
      raise_invalid_resource_list!(
        webpage: webpage,
        rdf_uris_count: rdf_uris.count,
        urls_count: urls.count,
        error: "URI count does not match URL count",
        field: URI_LIST_LABEL
      )
    end
  end

  def raise_invalid_resource_list!(webpage:, error:, field:, rdf_uris_count: nil, urls_count: nil)
    logger.error(
      resource_list_context(
        webpage: webpage,
        rdf_uris_count: rdf_uris_count,
        urls_count: urls_count
      ).merge(
        event: "resource_list.invalid",
        field: field,
        error: error
      )
    )
    raise InvalidResourceListError, error
  end

  def resource_list_context(webpage:, rdf_uris_count: nil, urls_count: nil)
    {
      webpage_id: webpage&.id,
      website_id: webpage&.website_id,
      resource_list_url: webpage&.url,
      rdf_uris_count: rdf_uris_count,
      urls_count: urls_count
    }
  end
end
