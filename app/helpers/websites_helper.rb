module WebsitesHelper
  include ApplicationHelper

  def display_time(t)
    return unless t

    t.strftime('%H:%M %Z')
  end

  def website_cache_links(website)
    active_cache_links_for(website.seedurl, website: website)
  end

  def website_rollout_badge(website)
    operator_rollout_badge(website)
  end

  def website_rollout_explanation(website)
    operator_rollout_explanation(website)
  end

  def website_rollout_filter_options
    options = Distillator::RolloutCopy.website_index_filter_options.dup
    return options unless Distillator::TransitionRuntime.staging?

    options + [["Invalid on staging", "invalid_on_staging"]]
  end

  def website_cohort_filter_options
    [
      ["All cohorts", ""],
      [Distillator::Cohorts::LavitrinePipeline.label, Distillator::Cohorts::LavitrinePipeline.key]
    ]
  end

  def website_rollout_filter_link(label:, mode:, current_filters:, current_sort:, current_direction:)
    params = current_filters.merge(distillator_mode: mode)
    params[:sort] = current_sort if current_sort.present?
    params[:direction] = current_direction if current_direction.present?
    link_to label, websites_path(params.compact)
  end

  def website_rollout_count(mode, rollout_counts)
    return website_invalid_on_staging_count if mode.to_s == "invalid_on_staging"

    counts = rollout_counts.to_h

    case mode.to_s
    when "unknown"
      counts[nil].to_i + counts[""].to_i
    else
      counts[mode.to_s].to_i
    end
  end

  def website_rollout_summary_items
    items = [
      { mode: "legacy", label: Distillator::RolloutCopy.label(:legacy) },
      { mode: "shadow", label: Distillator::RolloutCopy.label(:shadow) },
      { mode: "active", label: Distillator::RolloutCopy.label(:active) },
      { mode: "unknown", label: Distillator::RolloutCopy.label(:unknown) }
    ]
    return items unless Distillator::TransitionRuntime.staging?

    items + [{ mode: "invalid_on_staging", label: "Invalid on staging" }]
  end

  def website_rollout_summary_link(mode:, label:, rollout_counts:, current_sort:, current_direction:)
    count = website_rollout_count(mode, rollout_counts)
    params = { distillator_mode: mode == "unknown" ? "unknown" : mode }
    params[:sort] = current_sort if current_sort.present?
    params[:direction] = current_direction if current_direction.present?
    link_to "#{label}: #{count}", websites_path(params.compact), class: "website-rollout-summary-link"
  end

  def website_rollout_filter_form_options
    website_rollout_filter_options
  end

  def website_cohort_badge(website)
    label = website.distillator_primary_cohort_label
    return unless label.present?

    content_tag(:span, label, class: "rollout-badge rollout-badge-cohort")
  end

  def website_matches_cohort_filter?(website, cohort_filter)
    case cohort_filter.to_s
    when Distillator::Cohorts::LavitrinePipeline.key
      website.lavitrine_pipeline?
    else
      true
    end
  end

  def website_rollout_label_for(website)
    Distillator::RolloutCopy.label(website&.distillator_mode)
  end

  def website_rollout_description_for(website)
    Distillator::RolloutCopy.description(website&.distillator_mode)
  end

  def website_rollout_backend_for(website)
    operator_active_backend_label(website)
  end

  def website_webpages_filter_path(website, extra_params = {})
    webpages_path({ seedurl: website.seedurl }.merge(extra_params).compact)
  end

  def website_webpage_summary_cell(website, summary)
    data = summary || Distillator::WebsiteWebpageSummary.empty_summary
    lines = []

    lines << content_tag(:div, link_to("#{data[:total]} total", website_webpages_filter_path(website)))
    lines << content_tag(
      :div,
      safe_join(
        [
          website_webpage_summary_metric_link(website, count: data[:public_urls], text: "#{data[:public_urls]} public", params: { url_kind: "public" }),
          website_webpage_summary_separator,
          website_webpage_summary_metric_link(website, count: data[:internal_uris], text: "#{data[:internal_uris]} internal", params: { url_kind: "internal" })
        ]
      ),
      class: "muted"
    )
    lines << content_tag(:div, website_webpage_class_summary_links(website, data[:by_class]), class: "muted")
    lines << content_tag(
      :div,
      safe_join(
        [
          website_webpage_summary_metric_link(website, count: data[:publishable], text: "#{data[:publishable]} publishable", params: { publishable: true }),
          website_webpage_summary_separator,
          website_webpage_summary_metric_link(website, count: data[:not_publishable], text: "#{data[:not_publishable]} not publishable", params: { publishable: false })
        ]
      ),
      class: "muted"
    )

    content_tag(:div, safe_join(lines), class: "webpage-summary-cell")
  end

  def website_rollout_next_step_for(website)
    website_transition_summary(website).primary_action
  end

  def website_transition_contract(website)
    @website_transition_contracts ||= {}
    return inert_website_transition_contract unless website&.persisted?

    @website_transition_contracts[website.id] ||= begin
      mode = website.distillator_mode.presence || "legacy"
      summary = website_transition_summary(website)
      readiness = website_transition_readiness(website)
      blockers = Array(readiness.blockers)
      warnings = Array(readiness.warnings)
      primary_action = website_transition_primary_action(website, mode, readiness)

      {
        current_mode: mode,
        current_mode_label: website_rollout_label_for(website),
        backend_label: website_rollout_backend_for(website),
        next_action_label: primary_action[:label],
        next_mode: primary_action[:next_mode],
        action_enabled: primary_action[:enabled],
        blockers: blockers,
        warnings: warnings,
        override_allowed: website_transition_runtime_override_allowed?,
        rollback_available: mode == "active",
        next_recommended_action: summary.primary_action,
        readiness_summary: website_transition_readiness_summary(mode, blockers: blockers, warnings: warnings),
        latest_rollout_event_summary: website_transition_latest_event_summary(website),
        latest_rollout_event: website.rollout_events.order(created_at: :desc).first,
        cache_links: website_cache_panel_links(website),
        primary_action: primary_action,
        secondary_actions: website_transition_secondary_actions(website, mode, readiness),
        navigation_links: website_transition_navigation_links(website)
      }
    end
  end

  def website_transition_runtime_override_allowed?
    Distillator::TransitionRuntime.allow_active_override?
  end

  def website_transition_readiness(website)
    @website_transition_readiness ||= {}
    @website_transition_readiness[website.id] ||= Distillator::PromotionReadiness.call(
      website: website,
      cache: website_transition_cache(website),
      evidence_by_kind: website.latest_transition_evidences_by_kind
    )
  end

  def website_transition_latest_event_summary(website)
    event = website.rollout_events.order(created_at: :desc).first
    return "No rollout events recorded yet." unless event.present?

    summary = "#{event.from_mode.presence || 'unknown'} to #{event.to_mode} on #{event.created_at}"
    summary += " | blockers: #{Array(event.readiness_snapshot['blockers']).join(', ')}" if event.readiness_snapshot["blockers"].present?
    summary += " | warnings: #{Array(event.readiness_snapshot['warnings']).join(', ')}" if event.readiness_snapshot["warnings"].present?
    summary += " | reason: #{event.reason}" if event.reason.present?
    summary
  end

  def website_show_override_copy
    "Use after manual inspection or on staging. Records current blockers and reason."
  end

  def website_cache_panel_links(website)
    website_cache_links(website)
  end

  def website_transition_summary(website)
    @website_transition_summaries ||= {}
    @website_transition_summaries[website.id] ||= Distillator::ShadowSiteSummary.call(
      website: website,
      cache: website_transition_cache(website)
    )
  end

  def website_identity_rows(website)
    [
      ["Seedurl", website.seedurl],
      ["Default language", website.default_language],
      ["Graph name", website.graph_name]
    ]
  end

  def website_debug_id_label(website)
    "Website ##{website.id}"
  end

  def website_transition_report_path(website)
    distillator_shadow_report_site_path(website, anchor: "transition-report-summary")
  end

  def website_transition_status_summary(website)
    status = website_transition_status(website)
    return "Not checked yet." if status.status == :not_checked

    summary = [status.readiness_label]
    summary << "fetch #{status.fetch.to_s.humanize.downcase}"
    summary << "statements #{status.statements.to_s.humanize.downcase}"
    summary << "export #{status.export.to_s.humanize.downcase}"
    summary.join(" | ")
  end

  def website_transition_evidence_summary(website)
    evidence = website.latest_transition_evidences_by_kind.with_indifferent_access
    return "No transition evidence recorded yet." if evidence.blank?

    lines = []
    fetch = evidence["fetch_parity"]
    statements = evidence["statement_delta"]
    export = evidence["export_diff"]
    lines << "Fetch parity checked #{time_ago_in_words(fetch.checked_at)} ago." if fetch&.checked_at.present?
    lines << "Statement coverage #{statements.status}." if statements.present?
    lines << "Export comparison #{export.export_diff_status.presence || export.status}." if export.present?
    lines.join(" ")
  end

  def website_transition_batch_check_path
    distillator_transition_checks_path
  end

  def website_transition_batch_check_params(website, return_to:)
    { website_id: website.id }.merge(operator_return_to_params(return_to))
  end

  def website_transition_batch_check_copy
    "Transition checks are run by batch job. This page displays the latest result."
  end

  def website_transition_batch_status_path(website)
    website_path(website, anchor: "website-batch-jobs-transition")
  end

  def website_cache_diagnostics_path(website)
    cache = website_transition_cache(website)
    return distillator_cache_path(cache) if cache.present?

    distillator_cache_index_path(term: website.seedurl)
  end

  def website_publishable_event_pages_path(website)
    webpages_path(seedurl: website.seedurl)
  end

  def website_publishable_event_page_count(website)
    summary = Distillator::WebsiteWebpageSummary.for_websites([website.id])[website.id] || Distillator::WebsiteWebpageSummary.empty_summary
    summary[:publishable].to_i
  end

  def website_important_page_count(website)
    website.webpages.active.event_pages.count
  end

  def website_transition_status(website)
    @website_transition_statuses ||= {}
    @website_transition_statuses[website.id] ||= Distillator::TransitionStatus.call(
      website: website,
      cache: website_transition_cache(website),
      evidence_by_kind: website.latest_transition_evidences_by_kind
    )
  end

  def normalize_website_rollout_filter(raw_mode)
    mode = raw_mode.to_s.presence
    return nil if mode.blank?
    return "unknown" if mode == "unknown"
    return "invalid_on_staging" if Distillator::TransitionRuntime.staging? && mode == "invalid_on_staging"

    allowed = %w[legacy shadow active]
    allowed.include?(mode) ? mode : nil
  end

  def website_invalid_on_staging_count
    return 0 unless Distillator::TransitionRuntime.staging?

    Distillator::TransitionRuntime.staging_invalid_rollout_mode_scope.count
  end

  def website_staging_rollout_warning
    return unless Distillator::TransitionRuntime.staging?

    count = website_invalid_on_staging_count
    return if count.zero?

    "Staging requires every website to be Shadow or Active. #{count} websites are invalid on staging."
  end

  def normalize_website_cohort_filter(raw_cohort)
    cohort = raw_cohort.to_s.presence
    return nil if cohort.blank?

    allowed = [Distillator::Cohorts::LavitrinePipeline.key]
    allowed.include?(cohort) ? cohort : nil
  end

  private

  def website_webpage_class_summary_links(website, by_class)
    labels = [
      ["Event", "E"],
      ["Person", "Pe"],
      ["Place", "Pl"],
      ["ResourceList", "R"],
      ["WebPage", "W"],
      ["Other", "O"]
    ]

    safe_join(
      labels.flat_map.with_index do |(bucket, abbreviation), index|
        count = by_class.fetch(bucket, 0)
        node = website_webpage_summary_metric_link(
          website,
          count: count,
          text: "#{abbreviation}#{count}",
          params: { rdfs_class: bucket },
          title: webpage_class_bucket_title(bucket)
        )

        index.positive? ? [website_webpage_summary_separator, node] : [node]
      end
    )
  end

  def website_webpage_summary_metric_link(website, count:, text:, params:, title: nil)
    css_class = ["webpage-summary-link"]
    css_class << "muted" if count.to_i.zero?

    if count.to_i.zero?
      content_tag(:span, text, class: css_class.join(" "), title: title)
    else
      link_to text, website_webpages_filter_path(website, params), class: css_class.join(" "), title: title
    end
  end

  def website_webpage_summary_separator
    content_tag(:span, " · ", class: "webpage-summary-separator")
  end

  def webpage_class_bucket_title(bucket)
    case bucket
    when "Event"
      "Event webpages"
    when "Person"
      "Person webpages"
    when "Place"
      "Place webpages"
    when "ResourceList"
      "Resource list webpages"
    when "WebPage"
      "WebPage webpages"
    else
      "Other webpages"
    end
  end

  def inert_website_transition_contract
    {
      current_mode: "legacy",
      current_mode_label: Distillator::RolloutCopy.label(:legacy),
      backend_label: website_rollout_backend_for("legacy"),
      next_action_label: "Transition unavailable",
      next_mode: nil,
      action_enabled: false,
      blockers: [],
      warnings: [],
      override_allowed: false,
      rollback_available: false,
      next_recommended_action: "Select a saved website to review transition state.",
      readiness_summary: "Transition details are unavailable until the website is saved.",
      latest_rollout_event_summary: "No rollout events recorded yet.",
      latest_rollout_event: nil,
      cache_links: {},
      primary_action: {
        label: "Transition unavailable",
        next_mode: nil,
        enabled: false,
        path: nil,
        method: nil,
        params: {},
        message: "Save the website before changing transition state."
      },
      secondary_actions: [],
      navigation_links: []
    }
  end

  def website_transition_primary_action(website, mode, readiness)
    blockers = Array(readiness.blockers)
    warnings = Array(readiness.warnings)

    case mode
    when "legacy"
      {
        label: "Move to shadow",
        next_mode: "shadow",
        enabled: true,
        path: website_path(website),
        method: :patch,
        params: { website: { distillator_mode: "shadow" } }
      }
    when "shadow"
      if blockers.blank? && warnings.blank?
        {
          label: "Promote to active",
          next_mode: "active",
          enabled: true,
          path: website_path(website),
          method: :patch,
          params: { website: { distillator_mode: "active" } }
        }
      elsif readiness.review_activation_eligible
        {
          label: "Review before activating",
          next_mode: "active",
          enabled: false,
          path: nil,
          method: nil,
          params: {},
          message: "Only review-needed parity differences remain. Use Activate after review with a recorded reason."
        }
      else
        {
          label: "Cannot promote yet",
          next_mode: "active",
          enabled: false,
          path: nil,
          method: nil,
          params: {},
          message: (blockers.presence || warnings.presence || ["Transition checks are not complete."]).join(" ")
        }
      end
    else
      {
        label: "Rollback to Legacy Wringer",
        next_mode: "legacy",
        enabled: true,
        path: website_path(website),
        method: :patch,
        params: { website: { distillator_mode: "legacy" } }
      }
    end
  end

  def website_transition_secondary_actions(website, mode, readiness)
    actions = []

    if mode == "shadow" && readiness.review_activation_eligible
      actions << {
        kind: :override,
        label: "Activate after review",
        path: activate_after_review_website_path(website),
        method: :post,
        copy: "Use when only review-needed differences remain. Records the review reason and readiness snapshot."
      }
    elsif %w[legacy shadow].include?(mode) && website_transition_runtime_override_allowed?
      actions << {
        kind: :override,
        label: "Activate anyway",
        path: activate_anyway_website_path(website),
        method: :post,
        copy: website_show_override_copy
      }
    end

    actions
  end

  def website_transition_navigation_links(website)
    [
      { label: "Website", path: website_path(website) },
      { label: "Webpages", path: webpages_path(seedurl: website.seedurl) },
      { label: "Sources", path: sources_path(seedurl: website.seedurl) },
      { label: "Cache", path: distillator_cache_index_path },
      { label: "Transition report", path: distillator_shadow_report_site_path(website) },
      { label: "Options", path: options_path }
    ]
  end

  def website_transition_recommendation_for(mode, blockers:, warnings:)
    case mode
    when "legacy"
      "Move to shadow before promoting Condenser to production."
    when "shadow"
      return "Promote to active when the current checks are satisfactory." if blockers.blank?

      "Run the transition batch job and resolve blockers before promoting."
    when "active"
      "Use rollback only if production parity regresses."
    else
      "Confirm rollout configuration before promotion decisions."
    end
  end

  def website_transition_readiness_summary(mode, blockers:, warnings:)
    return blockers.join(" ") if blockers.any?
    return warnings.join(" ") if warnings.any?

    case mode
    when "shadow"
      "Ready for active promotion."
    when "active"
      "Latest recorded checks are clear."
    else
      "Transition checks become useful after the site moves to shadow."
    end
  end

  def website_transition_cache(website)
    @website_transition_caches ||= {}
    @website_transition_caches[website.id] ||= Distillator::ShadowReportQuery.latest_cache_for_website(website)
  end
end
