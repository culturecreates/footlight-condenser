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
    Distillator::RolloutCopy.website_index_filter_options
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
    counts = rollout_counts.to_h

    case mode.to_s
    when "unknown"
      counts[nil].to_i + counts[""].to_i
    else
      counts[mode.to_s].to_i
    end
  end

  def website_rollout_summary_items
    [
      { mode: "legacy", label: Distillator::RolloutCopy.label(:legacy) },
      { mode: "shadow", label: Distillator::RolloutCopy.label(:shadow) },
      { mode: "active", label: Distillator::RolloutCopy.label(:active) },
      { mode: "unknown", label: Distillator::RolloutCopy.label(:unknown) }
    ]
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

  def website_rollout_next_step_for(website)
    operator_rollout_next_step(website)
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

  def website_transition_ready?(website)
    readiness = website_transition_readiness(website)
    readiness.blockers.blank? && readiness.warnings.blank?
  end

  def website_transition_summary_for(website)
    readiness = website_transition_readiness(website)
    return "Ready for active promotion." if readiness.blockers.blank? && readiness.warnings.blank?
    return readiness.blockers.join(" ") if readiness.blockers.any?
    return readiness.warnings.join(" ") if readiness.warnings.any?

    "Transition checks have not been recorded yet."
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

  def website_show_transition_check_label(website)
    website.distillator_mode == "active" ? "Run transition check again" : "Run transition check"
  end

  def website_show_override_copy
    "Use after manual inspection or on staging. Records current blockers and reason."
  end

  def website_cache_panel_links(website)
    website_cache_links(website)
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

  def normalize_website_rollout_filter(raw_mode)
    mode = raw_mode.to_s.presence
    return nil if mode.blank?
    return "unknown" if mode == "unknown"

    allowed = %w[legacy shadow active]
    allowed.include?(mode) ? mode : nil
  end

  def normalize_website_cohort_filter(raw_cohort)
    cohort = raw_cohort.to_s.presence
    return nil if cohort.blank?

    allowed = [Distillator::Cohorts::LavitrinePipeline.key]
    allowed.include?(cohort) ? cohort : nil
  end

  private

  def website_transition_cache(website)
    @website_transition_caches ||= {}
    @website_transition_caches[website.id] ||= Distillator::ShadowReportQuery.latest_cache_for_website(website)
  end
end
