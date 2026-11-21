module Distillator::CapabilitiesHelper
  def capability_badges(labels)
    safe_join(Array(labels).map { |label| capability_badge(label) }, " ")
  end

  def capability_badge(label)
    content_tag(:span, label, class: capability_badge_css(label))
  end

  private

  def capability_badge_css(label)
    case label.to_s
    when "Implemented"
      "cache-badge cache-badge-http capability-badge"
    when "Legacy-backed"
      "rollout-badge rollout-badge-legacy capability-badge"
    when "Transition-only"
      "rollout-badge rollout-badge-shadow capability-badge"
    when "Production-critical"
      "cache-badge cache-badge-high capability-badge"
    when "Read-only"
      "cache-badge cache-badge-low capability-badge"
    when "Writes data"
      "cache-badge cache-badge-medium capability-badge"
    when "Needs review"
      "cache-badge cache-badge-medium capability-badge"
    when "Deprecated"
      "rollout-badge rollout-badge-unknown capability-badge"
    else
      "cache-badge cache-badge-unknown capability-badge"
    end
  end
end
