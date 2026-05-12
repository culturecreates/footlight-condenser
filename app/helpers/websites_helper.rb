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
    [
      ["All", nil],
      [Distillator::RolloutCopy.label(:legacy), "legacy"],
      [Distillator::RolloutCopy.label(:shadow), "shadow"],
      [Distillator::RolloutCopy.label(:active), "active"]
    ]
  end

  def website_rollout_filter_link(label:, mode:, current_filters:, current_sort:, current_direction:)
    params = current_filters.merge(distillator_mode: mode)
    params[:sort] = current_sort if current_sort.present?
    params[:direction] = current_direction if current_direction.present?
    link_to label, websites_path(params.compact)
  end

  def website_rollout_count(mode, rollout_counts)
    rollout_counts.to_h[mode.to_s].to_i
  end
end
