# Add new Webpages based on statements for Class ResourceList
class AddWebpagesJob < ApplicationJob
  queue_as :default

  RDF_CLASS_LABEL = 'RDF Class'
  DATA_ONLY_CLASS = 'None'
  URI_LIST_LABEL = 'URI List'
  WEBPAGE_URL_LIST_LABEL = 'Webpage URL List'
  InvalidResourceListError = Class.new(StandardError)

  def perform(webpage_id_or_url, selected_only: false, refresh_new: true, expected_discovery: nil)
    webpages = Webpage.includes(:website)
    webpage = if webpage_id_or_url.is_a?(Integer)
      webpages.find_by(id: webpage_id_or_url)
    else
      # Older jobs carry only a URL. Never choose between websites for them.
      matches = webpages.where(url: webpage_id_or_url).limit(2).to_a
      if matches.size > 1
        raise InvalidResourceListError, "ResourceList URL matches multiple webpages. Queue discovery from the intended website."
      end
      matches.first
    end
    return unless webpage

    statements = webpage.statements.includes(source: :property)
    if selected_only
      statements = statements.joins(:source).where(selected_individual: true, sources: { selected: true, website_id: webpage.website_id })
    end
    statements_by_label = statements.group_by { |statement| statement.source.property.label }
    class_statements = statements_by_label.fetch(RDF_CLASS_LABEL, [])
    data_only, discovery = class_statements.partition { |statement| statement.cache.to_s.strip == DATA_ONLY_CLASS }
    if data_only.any?(&:selected_individual?)
      logger.info(event: "resource_list.discovery_skipped", reason: "data_only", webpage_id: webpage.id, website_id: webpage.website_id)
      return
    end

    rdfs_class_name = discovery.last&.cache.to_s.strip
    if rdfs_class_name.blank?
      raise_invalid_resource_list!(webpage: webpage, error: "#{RDF_CLASS_LABEL} is blank", field: RDF_CLASS_LABEL)
    end

    rdf_uris = parse_json_array!(
      statements_by_label[URI_LIST_LABEL]&.last&.cache,
      label: URI_LIST_LABEL,
      webpage: webpage
    )
    urls = parse_json_array!(
      statements_by_label[WEBPAGE_URL_LIST_LABEL]&.last&.cache,
      label: WEBPAGE_URL_LIST_LABEL,
      webpage: webpage
    )

    validate_resource_list!(
      webpage: webpage,
      rdf_uris: rdf_uris,
      urls: urls
    )

    rdfs_class = RdfsClass.find_by!(name: rdfs_class_name)
    created_pages = []
    linked = false

    Webpage.transaction do
      webpage = Webpage.lock.find(webpage.id)
      linked = rdfs_class_name == "Event" && webpage.discovery_target_website_id.present?
      target = linked ? webpage.discovery_target_website : webpage.website
      if expected_discovery && (rdfs_class_name != "Event" || target.id != expected_discovery.fetch(:website_id) ||
          expected_discovery.fetch(:contents_digest) != Distillator::TransitionEventInventory.list_digest(urls, rdf_uris))
        raise InvalidResourceListError, "ResourceList destination or contents changed during discovery"
      end

      urls.each_with_index do |webpage_url, index|
        next if Webpage.exists?(url: webpage_url, website: target)

        created_pages << Webpage.create!(
          url: webpage_url,
          rdf_uri: rdf_uris[index],
          language: webpage.language,
          rdfs_class: rdfs_class,
          website: target
        )
      end
    end

    return created_pages.map(&:id) unless refresh_new

    created_pages.each { |page| RefreshWebpageJob.perform_later(linked ? page.id : page.url) }
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

  def validate_resource_list!(webpage:, rdf_uris:, urls:)
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
