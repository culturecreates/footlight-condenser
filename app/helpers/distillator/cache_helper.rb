module Distillator::CacheHelper
  HTML_PREVIEW_LIMIT = 160
  VIEW_MODES = %w[rich parity].freeze

  def cache_fetch_kind_label(fetch_kind, compact: false)
    case fetch_kind.to_s
    when "rendered"
      compact ? "Rendered fetch" : "Rendered fetch"
    when "post"
      compact ? "POST fetch" : "POST fetch"
    else
      "Direct fetch"
    end
  end

  def cache_fetch_kind_description(fetch_kind)
    case fetch_kind.to_s
    when "rendered"
      "Rendered fetch = JavaScript/rendered fetch with fragment support"
    when "post"
      "POST fetch = JSON POST source fetch"
    else
      "Direct fetch = normal cached fetch"
    end
  end

  def cache_fetch_kind_param(fetch_kind)
    fetch_kind.to_s.presence || "normal"
  end

  def cache_view_mode_label(view_mode)
    view_mode.to_s == "parity" ? "Compatibility view" : "Rich view"
  end

  def cache_operator_summary_cards(summary_cards)
    cards = cache_summary_card_lookup(summary_cards)
    [
      {
        title: "Healthy",
        count: cache_summary_card_count(cards, :healthy),
        tone: "healthy",
        description: "Rows with successful transport and usable content."
      },
      {
        title: "Needs review",
        count: cache_summary_card_count(cards, :stale),
        tone: "warning",
        description: "Rows that need operator review but are not outright failed."
      },
      {
        title: "Failed",
        count: cache_summary_card_count(cards, :network_failed) +
          cache_summary_card_count(cards, :blocked) +
          cache_summary_card_count(cards, :empty_body),
        tone: "failed",
        description: "Rows that failed to fetch or returned unusable content."
      },
      {
        title: "Preserved",
        count: cache_summary_card_count(cards, :preserved_after_failure),
        tone: "preserved",
        description: "Rows still serving last-good content after a failed refresh."
      },
      {
        title: "Never attempted",
        count: cache_summary_card_count(cards, :never_fetched),
        tone: "unknown",
        description: "Rows with no recorded scrape attempt yet."
      }
    ]
  end

  def cache_quick_filters
    [
      { label: "Needs review", params: { health: "stale" } },
      { label: "Content failed", params: { health: "preserved_after_failure" } },
      { label: "Last good preserved", params: { health: "preserved_after_failure" } },
      { label: "Network failed", params: { health: "network_failed" } },
      { label: "JSON", params: { content_type: "json" } },
      { label: "Redirected", params: { redirected: "true" } }
    ]
  end

  def cache_operator_health(payload)
    http_code = payload.fetch("http_response_code", payload[:http_response_code])
    network_status = cache_signal(payload, :network_status).to_s
    primary_issue_key = cache_blocking_issue_key(payload).to_s
    hints = cache_hints(payload).map(&:to_s)
    scrape_date = payload.fetch("scrape_date", payload[:scrape_date])
    successful_refresh = payload.fetch("successful_refresh", payload[:successful_refresh])
    health_label = payload.fetch("health_label", payload[:health_label]).presence
    health_status = payload.fetch("health_status", payload[:health_status]).presence

    if cache_last_good_content_preserved?(payload)
      return {
        state: :preserved,
        label: "Preserved",
        css_class: "cache-health-preserved",
        details: [health_label.presence || "Last good content preserved after failed refresh"].compact
      }
    end

    if Distillator::BooleanParam.parse(cache_signal(payload, :transport_success)) &&
        Distillator::BooleanParam.parse(cache_signal(payload, :content_success))
      return {
        state: :healthy,
        label: "Healthy",
        css_class: "cache-health-healthy",
        details: [health_label.presence || "Transport and content checks passed"].compact
      }
    end

    if network_status.in?(%w[blocked failed]) ||
        explicitly_false?(cache_signal(payload, :transport_success)) ||
        (http_code.present? && http_code.to_i >= 400)
      return {
        state: :failed,
        label: "Failed",
        css_class: "cache-health-failed",
        details: [
          health_label,
          network_status.presence,
          primary_issue_key.presence
        ].compact
      }
    end

    if warning_health?(payload, http_code: http_code, primary_issue_key: primary_issue_key, hints: hints)
      return {
        state: :warning,
        label: "Warning",
        css_class: "cache-health-warning",
        details: [
          health_label,
          primary_issue_key.presence,
          hints.find { |hint| operator_warning_hint?(hint) }
        ].compact
      }
    end

    if scrape_date.blank? && successful_refresh.blank?
      return {
        state: :unknown,
        label: "Unknown",
        css_class: "cache-health-unknown",
        details: [health_label.presence || "No scrape attempt recorded"].compact
      }
    end

    fallback_operator_health(payload, health_status: health_status, health_label: health_label)
  end

  def cache_health_badge(payload)
    operator_health = cache_operator_health(payload)
    content_tag(
      :span,
      operator_health.fetch(:label),
      class: "cache-badge cache-badge-health #{operator_health.fetch(:css_class)}",
      title: Array(operator_health[:details]).reject(&:blank?).join(" | ")
    )
  end

  def cache_status_badge(payload)
    code = payload.fetch("http_response_code", payload[:http_response_code])
    label = code.present? ? code.to_s : "nil"
    content_tag(:span, label, class: "cache-badge cache-badge-http")
  end

  def cache_signal_badge(label, value)
    content_tag(:span, "#{label}: #{value.presence || 'unknown'}", class: "cache-badge cache-badge-signal")
  end

  def cache_html_badge(payload)
    content_tag(:span, payload.fetch("has_html", payload[:has_html]) ? "Has HTML" : "Missing HTML", class: "cache-badge cache-badge-html")
  end

  def cache_redirected_badge(payload)
    redirected = cache_redirect_chain(payload).any? || payload.fetch("final_url", payload[:final_url]).to_s.present? && payload.fetch("final_url", payload[:final_url]).to_s != payload.fetch("normalized_url", payload[:normalized_url]).to_s
    content_tag(:span, redirected ? "Redirected" : "Direct", class: "cache-badge cache-badge-redirect")
  end

  def cache_redirect_summary(payload)
    hop_count = cache_redirect_chain(payload).count
    final_url = payload.fetch("final_url", payload[:final_url]).to_s
    normalized_url = payload.fetch("normalized_url", payload[:normalized_url]).to_s

    if hop_count.positive? || (final_url.present? && final_url != normalized_url)
      "Redirected (#{hop_count} hop#{'s' unless hop_count == 1})"
    else
      "Direct"
    end
  end

  def cache_timestamp_label(timestamp)
    return "Not recorded" if timestamp.blank?

    "#{timestamp} (#{time_ago_in_words(timestamp)} ago)"
  end

  def cache_signal(payload, key)
    payload.fetch("signals", payload[:signals] || {}).to_h[key.to_s] || payload.fetch("signals", payload[:signals] || {}).to_h[key.to_sym]
  end

  def cache_hints(payload)
    Array(payload.fetch("hints", payload[:hints] || []))
  end

  def cache_redirect_chain(payload)
    Array(payload.fetch("redirect_chain", payload[:redirect_chain] || []))
  end

  def cache_html_preview_text(payload)
    preview = payload.fetch("html_preview", payload[:html_preview] || nil).to_s
    return "Missing HTML" if preview.blank?

    truncate(preview, length: HTML_PREVIEW_LIMIT)
  end

  def cache_transport_status(payload)
    truthy = Distillator::BooleanParam.parse(cache_signal(payload, :transport_success))
    truthy ? "success" : "failed"
  end

  def cache_content_status(payload)
    truthy = Distillator::BooleanParam.parse(cache_signal(payload, :content_success))
    truthy ? "success" : "failed"
  end

  def cache_blocking_issue_key(payload)
    cache_signal(payload, :blocking_issue_key).presence || cache_signal(payload, :primary_issue_key).presence
  end

  def cache_blocking_issue_label(payload)
    cache_signal(payload, :primary_issue_label).presence ||
      cache_blocking_issue_key(payload).to_s.tr("_", " ").presence&.humanize
  end

  def cache_last_good_content_preserved?(payload)
    Distillator::BooleanParam.parse(cache_signal(payload, :last_good_preserved_failure))
  end

  def cache_content_failure_warning(payload)
    return nil unless Distillator::BooleanParam.parse(cache_signal(payload, :transport_success))
    return nil if Distillator::BooleanParam.parse(cache_signal(payload, :content_success))

    issue_label = cache_blocking_issue_label(payload).presence || "Content failure"
    "HTTP #{payload.fetch("http_response_code", payload[:http_response_code])} but content failed: #{issue_label}"
  end

  def cache_raw_url(cache)
    raw_distillator_cache_path(cache_id_for(cache))
  end

  def cache_raw_view_url(cache)
    raw_view_distillator_cache_path(cache_id_for(cache))
  end

  def cache_wring_json_url(cache)
    wring_json_distillator_cache_path(cache_id_for(cache))
  end

  def cache_wring_json_view_url(cache)
    wring_json_view_distillator_cache_path(cache_id_for(cache))
  end

  def cache_preview_url(cache, fetch_kind: "normal", extra_params: {})
    preview_distillator_cache_index_path(
      { uri: cache_normalized_url(cache), fetch_kind: cache_fetch_kind_param(fetch_kind) }.merge(extra_params)
    )
  end

  def cache_compare_url(cache)
    compare_distillator_cache_index_path(uri: cache_normalized_url(cache))
  end

  def legacy_wring_json_url(cache)
    wring_websites_path(format: :json, uri: cache_normalized_url(cache))
  end

  private

  def cache_summary_card_lookup(summary_cards)
    Array(summary_cards).index_by { |card| card[:key].to_sym }
  end

  def cache_summary_card_count(cards, key)
    cards.fetch(key, {}).fetch(:count, 0).to_i
  end

  def warning_health?(payload, http_code:, primary_issue_key:, hints:)
    return true if http_code.to_i == 200 && explicitly_false?(cache_signal(payload, :content_success))
    return true if primary_issue_key.present?
    return true if hints.any? { |hint| operator_warning_hint?(hint) }

    false
  end

  def operator_warning_hint?(hint)
    hint.to_s.in?(%w[
      redirect_to_listing
      queue_it
      waiting_room
      captcha
      blocked
      redirect_changed
    ])
  end

  def fallback_operator_health(payload, health_status:, health_label:)
    case health_status.to_s
    when "healthy"
      { state: :healthy, label: "Healthy", css_class: "cache-health-healthy", details: [health_label].compact }
    when "preserved_after_failure"
      { state: :preserved, label: "Preserved", css_class: "cache-health-preserved", details: [health_label.presence || "Last good content preserved after failed refresh"].compact }
    when "network_failed", "blocked", "attempt_failed", "empty_body"
      { state: :failed, label: "Failed", css_class: "cache-health-failed", details: [health_label].compact }
    when "redirect_changed", "stale"
      { state: :warning, label: "Warning", css_class: "cache-health-warning", details: [health_label].compact }
    else
      { state: :unknown, label: "Unknown", css_class: "cache-health-unknown", details: [health_label.presence || "Insufficient cache health metadata"].compact }
    end
  end

  def explicitly_false?(value)
    value == false || value.to_s == "false" || value.to_s == "0"
  end

  def cache_id_for(cache)
    cache.respond_to?(:id) ? cache.id : cache[:id]
  end

  def cache_normalized_url(cache)
    cache.respond_to?(:normalized_url) ? cache.normalized_url : cache[:normalized_url]
  end
end
