module SourcesHelper
  include ApplicationHelper

  QUICK_FILTERS = [
    ["website_defaults", "Website defaults"],
    ["alternatives", "Alternatives"],
    ["rendered_fetch", "Rendered fetch"],
    ["post_fetch", "POST fetch"],
    ["url_step", "URL step"],
    ["xpath", "XPath"],
    ["ruby_transform", "Ruby transform"],
    ["needs_test", "Needs test"]
  ].freeze

  ADVANCED_FILTER_KEYS = %i[
    quick_filter
    source_term
    source_property
    source_language
    source_selected_by
    source_status
    source_strategy
    source_pipeline
    source_needs_test
  ].freeze

  def sources_for_display(sources, filter_params: params)
    filtered = Array(sources)
    filter = filter_params[:quick_filter].to_s

    filtered = filtered.select { |source| source_matches_quick_filter?(source, filter) } if filter.present?

    term = filter_params[:source_term].to_s.strip.downcase
    if term.present?
      filtered = filtered.select do |source|
        [
          source_property_label(source),
          source.label,
          source.website&.seedurl,
          source.algorithm_value,
          source.selected_by
        ].compact.join(" ").downcase.include?(term)
      end
    end

    property_term = filter_params[:source_property].to_s.strip.downcase
    if property_term.present?
      filtered = filtered.select do |source|
        source_property_label(source).downcase.include?(property_term)
      end
    end

    language = filter_params[:source_language].to_s.strip.downcase
    if language.present?
      filtered = filtered.select { |source| source.language.to_s.strip.downcase == language }
    end

    selected_by = filter_params[:source_selected_by].to_s.strip.downcase
    if selected_by.present?
      filtered = filtered.select { |source| source.selected_by.to_s.strip.downcase.include?(selected_by) }
    end

    status_filter = filter_params[:source_status].to_s
    if status_filter.present?
      filtered = filtered.select { |source| source_operator_status(source)[:key] == status_filter }
    end

    strategy_filter = filter_params[:source_strategy].to_s
    if strategy_filter.present?
      filtered = filtered.select { |source| source_fetch_strategy(source)[:key] == strategy_filter }
    end

    pipeline_filter = filter_params[:source_pipeline].to_s
    if pipeline_filter.present?
      filtered = filtered.select { |source| source_pipeline_flags(source)[pipeline_filter.to_sym] }
    end

    needs_test_filter = filter_params[:source_needs_test].to_s
    if needs_test_filter.present?
      expected = ActiveModel::Type::Boolean.new.cast(needs_test_filter)
      filtered = filtered.select { |source| source_needs_test?(source) == expected }
    end

    filtered
  end

  def source_quick_filter_links(sources, filter_params: params)
    display_sources = Array(sources)

    QUICK_FILTERS.map do |key, label|
      {
        key: key,
        label: label,
        count: display_sources.count { |source| source_matches_quick_filter?(source, key) },
        active: filter_params[:quick_filter].to_s == key,
        path: source_filter_path({ quick_filter: key }, filter_params: filter_params)
      }
    end
  end

  def source_clear_filters_path(filter_params: params)
    source_filter_path({ quick_filter: nil }.merge(ADVANCED_FILTER_KEYS.index_with { nil }), filter_params: filter_params)
  end

  def source_filters_form_path
    request.path
  end

  def source_advanced_filters_open?(filter_params: params)
    ADVANCED_FILTER_KEYS.any? do |key|
      next false if key == :quick_filter

      filter_params[key].present?
    end
  end

  def source_filter_hidden_fields(form)
    form.hidden_field(:seedurl, value: params[:seedurl]) +
      form.hidden_field(:id, value: params[:id]) +
      form.hidden_field(:quick_filter, value: params[:quick_filter])
  end

  def source_operator_status(source)
    latest_statement = source_latest_statement(source)

    if latest_statement&.status.to_s.in?(%w[problem missing])
      {
        key: "failed",
        label: "Failed",
        css_class: "source-status-failed",
        detail: "Latest statement status: #{latest_statement.status}"
      }
    elsif source_needs_test?(source)
      {
        key: "needs_test",
        label: "Needs test",
        css_class: "source-status-needs-test",
        detail: "No statement cache exists yet."
      }
    elsif source.selected? && manual_sensitive_source?(source)
      {
        key: "manual_sensitive",
        label: "Manual-sensitive",
        css_class: "source-status-manual",
        detail: "Selected by #{source.selected_by}."
      }
    elsif source.selected?
      {
        key: "website_default",
        label: "Website default",
        css_class: "source-status-default",
        detail: "Primary source for this property and language."
      }
    else
      {
        key: "alternative",
        label: "Alternative",
        css_class: "source-status-alternative",
        detail: "Available but not selected for this website."
      }
    end
  end

  def source_status_badge(source)
    status = source_operator_status(source)
    content_tag(:span, status[:label], class: "source-status-badge #{status[:css_class]}")
  end

  def source_property_language_text(source)
    parts = [source_property_label(source)]
    parts << "@#{source.language}" if source.language.present?
    parts.join(" ")
  end

  def source_property_name(source)
    source.property&.label.presence || "No property"
  end

  def source_label_text(source)
    source.label.presence || "Unlabeled"
  end

  def source_algorithm_text(source)
    source.algorithm_value.presence || "No extraction DSL defined."
  end

  def source_boolean_text(value)
    value ? "Yes" : "No"
  end

  def source_property_context(source)
    details = []
    details << source.property&.rdfs_class&.name
    details << source.label.presence
    details.compact.join(" • ")
  end

  def source_pipeline_summary(source)
    flags = source_pipeline_flags(source)
    labels = []
    labels << "URL step" if flags[:url_step]
    labels << "XPath" if flags[:xpath]
    labels << "Ruby transform" if flags[:ruby_transform]
    labels << "POST step" if flags[:post_fetch]
    labels << "Fixture/static" if labels.empty?
    labels
  end

  def source_fetch_strategy(source)
    if source.json_post?
      { key: "post_fetch", label: "POST fetch", detail: "Uses a POST request to fetch source content." }
    elsif source.render_js?
      { key: "rendered_fetch", label: "Rendered fetch", detail: "Uses rendered/JavaScript fetch behavior." }
    else
      { key: "direct_fetch", label: "Direct fetch", detail: "Uses the normal cached fetch path." }
    end
  end

  def source_fetch_strategy_badge(source)
    strategy = source_fetch_strategy(source)
    content_tag(:span, strategy[:label], class: "source-fetch-badge")
  end

  def source_impact_summary(source)
    parts = []
    parts << (source.selected? ? "Default scope" : "Alternative scope")
    parts << "#{source_statement_count(source)} statement#{'s' unless source_statement_count(source) == 1}"
    parts << "Auto review" if source.auto_review?
    parts.join(" • ")
  end

  def source_activation_impact(source)
    if source.selected?
      "This source is the website default for this property/language."
    else
      "Activating this source will make it the website default for this property/language and replace the current default source for that scope."
    end
  end

  def source_activation_detail(source)
    if source.selected?
      "Related statements currently follow this source for the shared property/language scope."
    else
      "Related statements for the same property/language scope will switch to this source when you activate it."
    end
  end

  def source_extraction_rule_summary(source)
    source.algorithm_value.present? ? truncate(source.algorithm_value.to_s, length: 120) : "No extraction DSL defined."
  end

  def source_form_fetch_strategy_summary(source)
    labels = []
    labels << "Rendered fetch" if source.render_js?
    labels << "POST fetch" if source.json_post?
    labels << "Direct fetch" if labels.empty?
    labels.join(" • ")
  end

  def source_form_fetch_strategy_note(source)
    notes = []
    notes << "Rendered fetch uses JavaScript/rendered page retrieval." if source.render_js?
    notes << "POST fetch is controlled by the DSL when a post_url= step is present." if source.json_post?
    notes << "Include fragment and absolute-src behavior stay in the DSL/fetch pipeline; there are no separate form fields here." 
    notes.join(" ")
  end

  def source_last_test_summary(source)
    statement = source_latest_statement(source)
    return "Needs test" unless statement

    timestamp = statement.updated_at.present? ? l(statement.updated_at, format: :short) : "Unknown time"
    "#{statement.status.to_s.titleize} • #{timestamp}"
  end

  def source_last_test_detail(source)
    statement = source_latest_statement(source)
    return "No statement has been refreshed from this source yet." unless statement

    "Statement ##{statement.id} on webpage ##{statement.webpage_id}"
  end

  def source_inline_test_action(source)
    statement = source_latest_statement(source)
    if statement
      button_to "Test", refresh_statement_path(statement), method: :patch, form_class: "inline", class: "as-link"
    elsif (webpage = source_target_webpage(source))
      button_to "Test", refresh_rdf_uri_statements_path(rdf_uri: webpage.rdf_uri), method: :patch, form_class: "inline", class: "as-link"
    else
      content_tag(:span, "Test unavailable", class: "source-action-disabled")
    end
  end

  def source_inline_trace_action(source)
    statement = source_latest_statement(source)
    return content_tag(:span, "Trace unavailable", class: "source-action-disabled") unless statement

    link_to "Trace", statement_path(statement)
  end

  def source_more_actions(source)
    safe_join(source_action_groups(source))
  end

  def source_metadata_pairs(source)
    [
      ["Source ID", source.id],
      ["Website ID", source.website_id],
      ["Raw selected value", source.selected.inspect],
      ["Selected by", source.selected_by.presence || "Not recorded"],
      ["Raw DSL", source.algorithm_value.to_s],
      ["Created", source.created_at.present? ? l(source.created_at, format: :short) : "Unknown"],
      ["Updated", source.updated_at.present? ? l(source.updated_at, format: :short) : "Unknown"]
    ]
  end

  def source_diagnostics_pairs(source)
    pairs = source_metadata_pairs(source)
    statement = source_latest_statement(source)
    pairs + [
      ["Statement count", source_statement_count(source)],
      ["Latest statement", statement.present? ? "##{statement.id} (#{statement.status})" : "None yet"]
    ]
  end

  def source_cache_note(source)
    links = source_cache_links(source)
    return "Related cache links are unavailable until a webpage is associated with this source." if links.blank? || links[:disabled]

    links[:warning].presence || "Related cache links use the current rollout-safe cache resolver."
  end

  def source_cache_rollout_badge(source)
    links = source_cache_links(source)
    return if links.blank? || links[:disabled]

    operator_active_backend_badge(links)
  end

  def source_rollout_badge(source)
    operator_rollout_badge(source.website)
  end

  def source_rollout_explanation(source)
    operator_rollout_explanation(source.website)
  end

  def source_show_back_path(source)
    return website_sources_path(id: source.website_id) if params[:from] == "website"

    sources_path(seedurl: params[:seedurl].presence)
  end

  def source_form_identity_pairs(source)
    [
      ["Website", source.website&.seedurl.presence || "Choose a website"],
      ["Property", source.property&.label.presence || "Choose a property"],
      ["Class", source.property&.rdfs_class&.name.presence || @rdfs_class_name],
      ["Language", source.language.presence || "Language-independent"]
    ]
  end

  private

  def source_matches_quick_filter?(source, filter_key)
    case filter_key.to_s
    when "website_defaults"
      source.selected?
    when "alternatives"
      !source.selected?
    when "rendered_fetch"
      source.render_js?
    when "post_fetch"
      source.json_post?
    when "url_step"
      source_pipeline_flags(source)[:url_step]
    when "xpath"
      source_pipeline_flags(source)[:xpath]
    when "ruby_transform"
      source_pipeline_flags(source)[:ruby_transform]
    when "needs_test"
      source_needs_test?(source)
    else
      true
    end
  end

  def source_filter_path(overrides = {}, filter_params: params)
    query = request.query_parameters.symbolize_keys.slice(:seedurl, :id, *ADVANCED_FILTER_KEYS).merge(overrides)
    query.delete_if { |_key, value| value.blank? }
    query_string = query.to_query
    query_string.present? ? "#{request.path}?#{query_string}" : request.path
  end

  def manual_sensitive_source?(source)
    source.selected_by.present? && source.selected_by.to_s != "Distillator"
  end

  def source_property_label(source)
    property = source.property
    class_name = property&.rdfs_class&.name
    property_name = property&.label

    [class_name, property_name].compact.join(" / ")
  end

  def source_pipeline_flags(source)
    @source_pipeline_flags ||= {}
    @source_pipeline_flags[source.id] ||= begin
      steps = source.algorithm_value.to_s.split(";").map(&:strip).reject(&:blank?)
      {
        url_step: steps.any? { |step| step.start_with?("url=", "post_url=") || step.include?("$url") },
        xpath: steps.any? { |step| step.start_with?("xpath=", "xpath_sanitize=") },
        ruby_transform: steps.any? { |step| step.start_with?("ruby=") },
        post_fetch: steps.any? { |step| step.start_with?("post_url=") }
      }
    end
  end

  def source_needs_test?(source)
    source_latest_statement(source).blank?
  end

  def source_latest_statement(source)
    @source_latest_statements ||= {}
    @source_latest_statements[source.id] ||= source.statements.order(updated_at: :desc).first
  end

  def source_target_webpage(source)
    @source_target_webpages ||= {}
    @source_target_webpages[source.id] ||= begin
      latest_statement = source_latest_statement(source)
      latest_statement&.webpage ||
        source.website.webpages.where(rdfs_class_id: source.property.rdfs_class_id).order(:id).first
    end
  end

  def source_statement_count(source)
    @source_statement_counts ||= {}
    @source_statement_counts[source.id] ||= source.statements.count
  end

  def source_cache_links(source)
    @source_cache_links ||= {}
    @source_cache_links[source.id] ||= begin
      webpage = source_target_webpage(source)
      webpage ? active_cache_links_for(webpage.url, website: source.website) : nil
    end
  end

  def source_more_action_items(source)
    statement = source_latest_statement(source)
    links = source_cache_links(source)
    {
      primary: [
        if statement
          button_to("Activate", activate_statement_path(statement), method: :patch, form_class: "inline", class: "as-link")
        else
          content_tag(:span, "Activate unavailable", class: "source-action-disabled")
        end
      ],
      diagnostics: [
        link_or_disabled("Open active cache", links&.dig(:active_cache_url)),
        link_or_disabled(Distillator::RolloutCopy.condenser_cache_label, links&.dig(:distillator_cache_url)),
        link_or_disabled(Distillator::RolloutCopy.compare_label, links&.dig(:compare_url)),
        link_or_disabled(Distillator::RolloutCopy.legacy_inspection_label, links&.dig(:legacy_cache_url)),
        link_to("Report", source_reports_path(source_id: source.id))
      ],
      danger: [
        link_to("Delete", source_path(source), method: :delete, data: { confirm: "Are you sure?", turbo: false })
      ]
    }
  end

  def link_or_disabled(label, href)
    return content_tag(:span, label, class: "source-action-disabled") if href.blank?

    link_to label, href
  end

  def source_action_groups(source)
    groups = source_more_action_items(source)

    [
      source_action_group_section("Primary", groups[:primary]),
      source_action_group_section("Diagnostics", groups[:diagnostics]),
      source_action_group_section("Danger zone", groups[:danger], extra_class: "source-action-group-danger")
    ]
  end

  def source_action_group_section(title, items, extra_class: nil)
    content_tag(:section, class: ["source-action-section", extra_class].compact.join(" ")) do
      content_tag(:strong, title) +
        content_tag(:ul, class: "source-more-actions-list") do
          safe_join(Array(items).map { |item| content_tag(:li, item) })
        end
    end
  end
end
