module OperatorContextHelper
  def operator_context_payload
    website = operator_context_website
    webpage = operator_context_webpage
    source = operator_context_source
    statement = operator_context_statement
    cache = operator_context_cache
    cache_payload = operator_context_cache_payload(cache)
    url = operator_context_url(webpage: webpage, statement: statement, cache_payload: cache_payload, cache: cache)
    cache_links = url.present? ? active_cache_links_for(url, website: website, website_id: website&.id) : nil

    payload = {
      website: website,
      rollout: website || cache_links,
      source: source,
      webpage: webpage,
      statement: statement,
      cache: cache,
      cache_payload: cache_payload,
      diagnostics: operator_context_diagnostics(
        website: website,
        webpage: webpage,
        source: source,
        statement: statement,
        cache: cache,
        cache_links: cache_links
      ),
      cache_links: cache_links
    }

    payload if operator_context_payload_present?(payload)
  end

  def operator_context_present?
    operator_context_payload_present?(operator_context_payload)
  end

  def operator_context_status_rows(context)
    rows = []

    if context[:cache_payload].present?
      rows << ["Cache health", cache_health_badge(context[:cache_payload])]
      rows << ["HTTP", context[:cache_payload][:http_response_code] || context[:cache_payload]["http_response_code"] || "Not recorded"]
      rows << ["Last successful refresh", context[:cache_payload][:successful_refresh] || context[:cache_payload]["successful_refresh"] || "Not recorded"]
    elsif context[:statement].present?
      rows << ["Statement status", context[:statement].status]
      rows << ["Status origin", context[:statement].status_origin]
      rows << ["Cache refreshed", context[:statement].cache_refreshed || "Not recorded"]
    end

    if context[:cache_links].present? && context[:cache_links][:warning].present?
      rows << ["Warning", context[:cache_links][:warning]]
    end

    rows
  end

  def operator_context_action_links(context)
    links = []
    cache_links = context[:cache_links] || {}

    if cache_links[:active_cache_url].present?
      links << { label: cache_links[:label], url: cache_links[:active_cache_url] }
    end

    secondary = Array(cache_links[:secondary_links])
    secondary.each do |link|
      links << link if %w[Compare Condenser vs Wringer Inspect legacy Wringer Open Condenser cache].include?(link[:label])
    end

    url = operator_context_url(
      webpage: context[:webpage],
      statement: context[:statement],
      cache_payload: context[:cache_payload],
      cache: context[:cache]
    )

    if url.present?
      links << { label: "Diagnose refresh", url: distillator_refresh_preview_url_for(url) }
    end

    links.uniq { |link| [link[:label], link[:url]] }
  end

  def operator_context_detail_rows(context)
    website = context[:website]
    webpage = context[:webpage]
    source = context[:source]
    statement = context[:statement]
    cache = context[:cache]
    cache_links = context[:cache_links] || {}

    rows = []
    rows << ["Selected URL", operator_context_url(webpage: webpage, statement: statement, cache_payload: context[:cache_payload], cache: cache)] if webpage.present? || statement.present? || cache.present? || context[:cache_payload].present?
    rows << ["Webpage", webpage.url] if webpage.present?
    rows << ["Source", source_property_language_text(source)] if source.present?
    rows << ["Fetch strategy", source_fetch_strategy_badge(source)] if source.present?
    rows << ["Pipeline", source_pipeline_summary(source).join(" • ")] if source.present?
    rows << ["Statement id", statement.id] if statement.present?
    rows << ["Cache id", cache.id] if cache.present?
    rows << ["Fetch kind", params[:fetch_kind]] if params[:fetch_kind].present?
    rows += Array(context[:diagnostics])
    rows.reject { |_label, value| value.blank? }
  end

  private

  def operator_context_payload_present?(payload)
    return false if payload.blank?

    %i[website source webpage statement cache cache_payload].any? { |key| payload[key].present? }
  end

  def operator_context_website
    return @website if instance_variable_defined?(:@website) && @website.present?
    return @webpage.website if instance_variable_defined?(:@webpage) && @webpage&.website.present?
    return @source.website if instance_variable_defined?(:@source) && @source&.website.present?
    return @statement.webpage.website if instance_variable_defined?(:@statement) && @statement&.webpage&.website.present?

    nil
  end

  def operator_context_webpage
    return @webpage if instance_variable_defined?(:@webpage) && @webpage.present?
    return @statement.webpage if instance_variable_defined?(:@statement) && @statement&.webpage.present?

    nil
  end

  def operator_context_source
    return @source if instance_variable_defined?(:@source) && @source.present?
    return @statement.source if instance_variable_defined?(:@statement) && @statement&.source.present?

    nil
  end

  def operator_context_statement
    return @statement if instance_variable_defined?(:@statement) && @statement.present?

    nil
  end

  def operator_context_cache
    return @cache if instance_variable_defined?(:@cache) && @cache.present?

    nil
  end

  def operator_context_cache_payload(cache)
    return @cache_payload if instance_variable_defined?(:@cache_payload) && @cache_payload.present?
    return nil unless cache.present?

    {
      id: cache.id,
      normalized_url: cache.respond_to?(:normalized_url) ? cache.normalized_url : nil,
      uri_key: cache.respond_to?(:uri_key) ? cache.uri_key : nil,
      http_response_code: cache.respond_to?(:http_response_code) ? cache.http_response_code : nil,
      name: cache.respond_to?(:name) ? cache.name : nil,
      scrape_date: cache.respond_to?(:scrape_date) ? cache.scrape_date : nil,
      successful_refresh: cache.respond_to?(:successful_refresh) ? cache.successful_refresh : nil,
      signals: cache.respond_to?(:signals) ? cache.signals : {},
      hints: cache.respond_to?(:hints) ? cache.hints : [],
      health_label: cache.respond_to?(:health_label) ? cache.health_label : nil,
      health_status: cache.respond_to?(:health_status) ? cache.health_status : nil
    }
  end

  def operator_context_url(webpage:, statement:, cache_payload:, cache:)
    return webpage.url if webpage&.url.present?
    return statement.webpage.url if statement&.webpage&.url.present?
    return cache_payload[:normalized_url] if cache_payload&.dig(:normalized_url).present?
    return cache_payload["normalized_url"] if cache_payload&.dig("normalized_url").present?
    return cache.normalized_url if cache.respond_to?(:normalized_url) && cache.normalized_url.present?

    nil
  end

  def operator_context_diagnostics(website:, webpage:, source:, statement:, cache:, cache_links:)
    diagnostics = []
    diagnostics << ["Website id", website.id] if website.present?
    diagnostics << ["Webpage id", webpage.id] if webpage.present?
    diagnostics << ["Source id", source.id] if source.present?
    diagnostics << ["Statement id", statement.id] if statement.present?
    diagnostics << ["Cache id", cache.id] if cache.present?
    diagnostics << ["Cache warning", cache_links[:warning]] if cache_links.present? && cache_links[:warning].present?
    diagnostics
  end
end
