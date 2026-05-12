module ApplicationHelper
  include AdminTableHelper

  def list_of_websites
    @list_of_websites ||= Website.all.order(:name)
  end

  def active_cache_links_for(url, include_fragment: false, mode: nil, website: nil, website_id: nil)
    Distillator::CacheLinkResolver.call(
      url: url,
      include_fragment: include_fragment,
      mode: mode,
      website: website,
      website_id: website_id
    )
  end

  def distillator_refresh_preview_url_for(url, include_fragment: false)
    params = { uri: url.to_s }
    params[:include_fragment] = true if include_fragment
    "/distillator/cache/preview?#{params.to_query}"
  end

  def sortable(column, label = nil)
    admin_sortable(column, label)
  end

  def operator_rollout_badge(website_or_mode)
    state = operator_rollout_state(website_or_mode)
    content_tag(:span, state[:label], class: "rollout-badge #{state[:css_class]}")
  end

  def operator_rollout_explanation(website_or_mode)
    operator_rollout_state(website_or_mode)[:description]
  end

  def operator_active_backend_badge(rollout_or_cache)
    state = operator_active_backend_state(rollout_or_cache)
    content_tag(:span, state[:label], class: "active-backend-badge #{state[:css_class]}")
  end

  def operator_active_backend_state(rollout_or_cache)
    rollout_key = normalize_rollout_state(rollout_or_cache)

    case rollout_key
    when :active
      { key: :active, label: "Active: Condenser", css_class: "active-backend-badge-active" }
    when :shadow
      { key: :shadow, label: "Active: Wringer + Shadow comparison", css_class: "active-backend-badge-shadow" }
    when :replay
      { key: :replay, label: "Active: Replay diagnostic", css_class: "active-backend-badge-replay" }
    else
      { key: :legacy, label: "Active: Wringer", css_class: "active-backend-badge-legacy" }
    end
  end

  def operator_rollout_state(website_or_mode)
    key = normalize_rollout_state(website_or_mode)
    Distillator::RolloutCopy.state(key).merge(key: key)
  end

  private

  def normalize_rollout_state(website_or_mode)
    raw_mode =
      case website_or_mode
      when nil
        nil
      when Hash
        website_or_mode[:rollout_mode] ||
          website_or_mode["rollout_mode"] ||
          website_or_mode[:mode] ||
          website_or_mode["mode"]
      else
        if website_or_mode.respond_to?(:distillator_mode)
          website_or_mode.distillator_mode
        elsif website_or_mode.respond_to?(:rollout_mode)
          website_or_mode.rollout_mode
        elsif website_or_mode.respond_to?(:mode)
          website_or_mode.mode
        else
          website_or_mode
        end
      end

    Distillator::RolloutCopy.normalize(raw_mode)
  end

end
