# Helper used in mulitple places
module WebpagesHelper
  include ApplicationHelper

  # Check for missing required properties
  # TODO: replace this with SHACL
  def missing_required_properties(event_statement_collection)
    # receive a set of statements for an event and check if the event is publishable
    mandatory_schema = ["http://schema.org/name", "http://schema.org/startDate", "http://schema.org/location"]
    problem_statements = event_statement_collection.select{ |s| s[:rdfs_class_name] == "Event" && mandatory_schema.include?(s[:predicate]) && (( s['status'] != "ok" && s['status']  != "updated")  || s[:value] == "[]" ||  s[:value].blank? ) }

    # Virtual Location removes location error if valid
    if event_statement_collection.select { |s| s[:label] == "VirtualLocation" && (( s['status'] == "ok" || s['status']  == "updated")  && s[:value] != "[]" &&  s[:value].present? )}.count > 0
      problem_statements.reject! { |s| s[:predicate] == "http://schema.org/location" }
    end

    problem_statements
  end

  def webpage_cache_links(webpage)
    active_cache_links_for(webpage.url, website: webpage.website)
  end

  def webpage_cache_panel_links(webpage)
    links = webpage_cache_links(webpage).dup
    warning = webpage_cache_warning_for(webpage, links)
    warning.present? ? links.merge(warning: warning) : links
  end

  def webpage_rollout_badge(webpage)
    operator_rollout_badge(webpage.website)
  end

  def webpage_rollout_explanation(webpage)
    operator_rollout_explanation(webpage.website)
  end

  def webpage_rollout_label_for(webpage)
    Distillator::RolloutCopy.label(webpage&.website&.distillator_mode)
  end

  def webpage_rollout_backend_for(webpage)
    operator_active_backend_label(webpage.website)
  end

  def webpage_rollout_next_step_for(webpage, cache_links: webpage_cache_links(webpage))
    if webpage_cache_not_inspectable?(webpage, cache_links)
      "Use Diagnose refresh to inspect why this URL is not cache-inspectable."
    else
      operator_rollout_next_step(webpage.website)
    end
  end

  def webpage_identity_rows(webpage)
    [
      ["Website", webpage_website_label(webpage)],
      ["RDF URI", webpage.rdf_uri],
      ["RDFS class", webpage.rdfs_class&.name],
      ["Language", webpage.language],
      ["JSON-LD output", webpage_jsonld_output_label(webpage)],
      ["Created", webpage.created_at],
      ["Updated", webpage.updated_at],
      ["Archive date", webpage.archive_date]
    ]
  end

  def webpage_debug_id_label(webpage)
    "Webpage ##{webpage.id}"
  end

  def webpages_selected_rdfs_class_id(filters)
    explicit_id = filters[:rdfs_class_id].presence
    return explicit_id if explicit_id.present?

    class_name = filters[:rdfs_class].to_s
    return nil if class_name.blank? || class_name == "Other"

    RdfsClass.find_by(name: class_name)&.id
  end

  def webpages_index_summary_heading(website:, visible_count:, filtered_count:, total_count:, filters:)
    page_label = "publishable event #{'page'.pluralize(visible_count)}"
    return "Showing #{visible_count} matching webpages." if webpages_all_scope?(filters)
    return "Showing #{visible_count} #{page_label}." unless website.present?

    "Showing #{visible_count} #{page_label} for this website."
  end

  def webpages_index_summary_secondary_lines(website:, summary:, filters:, total_count:)
    return [] unless website.present? && summary.present?

    lines = []
    if webpages_all_scope?(filters) || webpages_filter_active?(filters)
      lines << "Total website webpages: #{total_count}."
    end

    lines << "#{summary[:public_urls]} public source URLs · #{summary[:internal_uris]} internal entity URIs"
    lines << [
      "Events #{summary[:by_class]['Event']}",
      "People #{summary[:by_class]['Person']}",
      "Places #{summary[:by_class]['Place']}",
      "Resource lists #{summary[:by_class]['ResourceList']}",
      "Web pages #{summary[:by_class]['WebPage']}",
      "Other #{summary[:by_class]['Other']}"
    ].join(" · ")
    lines << "Publishable #{summary[:publishable]} · Not publishable #{summary[:not_publishable]}"
    lines
  end

  def webpages_all_scope?(filters)
    filters[:scope].to_s == "all"
  end

  def webpages_scope_toggle_path(filters:, seedurl:, target_scope:)
    scope_filters = filters.to_h.symbolize_keys.except(:scope, :publishable, :website_id)
    scope_filters[:scope] = "all" if target_scope.to_s == "all"
    scope_filters[:seedurl] = seedurl if seedurl.present?

    webpages_path(scope_filters.compact_blank)
  end

  def webpage_cache_warning_for(webpage, cache_links)
    return "Invalid cache URL. Use Diagnose refresh to inspect why this URL is not cache-inspectable." if webpage_cache_not_inspectable?(webpage, cache_links)

    cache_links[:warning]
  end

  private

  def webpage_cache_not_inspectable?(webpage, cache_links)
    cache_links[:disabled] || !webpage_cache_inspectable_url?(webpage.url)
  end

  def webpage_cache_inspectable_url?(url)
    key = Distillator::WringerUrlKey.call(url)
    key.normalized_url.start_with?("http://", "https://")
  rescue StandardError
    false
  end

  def webpage_jsonld_output_label(webpage)
    webpage.jsonld_output&.name || "System default"
  end

  def webpage_website_label(webpage)
    website = webpage.website
    return "Not assigned" if website.blank?

    name = website.name.presence
    seedurl = website.seedurl.presence

    return [name, "(#{seedurl})"].join(" ") if name.present? && seedurl.present?
    return name if name.present?

    seedurl
  end

  def webpages_filter_active?(filters)
    filters.slice(:term, :language, :rdfs_class_id, :rdfs_class, :archive_state, :url_kind, :publishable).values.any?(&:present?)
  end

  def webpages_filter_label(filters)
    return "publishable" if filters[:publishable].to_s == "true"
    return "not publishable" if filters[:publishable].to_s == "false"
    return "public source URL" if filters[:url_kind].to_s == "public"
    return "internal entity URI" if filters[:url_kind].to_s == "internal"

    if filters[:rdfs_class_id].present?
      label = RdfsClass.find_by(id: filters[:rdfs_class_id])&.name
      return label if label.present?
    end

    filters[:rdfs_class].presence || ("matching" if webpages_filter_active?(filters))
  end
end
