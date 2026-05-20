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

  def website_cache_panel_links(website)
    website_cache_links(website)
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
end
