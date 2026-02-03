require "uri"

module CcWringerHelper
  def use_wringer(url, render_js = false, options = {})
    defaults = { force_scrape_every_hrs: nil }
    options = defaults.merge(options)
    url = url.first if url.is_a?(Array)
    url = normalize_url(url)

    query = {
      uri: url,
      format: "raw",
      include_fragment: "true"
    }
    query[:use_phantomjs] = "true" if render_js
    query[:force_scrape_every_hrs] = options[:force_scrape_every_hrs] if options[:force_scrape_every_hrs]
    query[:json_post] = "true" if options[:json_post]

    path = "/websites/wring?#{URI.encode_www_form(query)}"
    logger.info("*** calling wringer with: #{get_wringer_url_per_environment}#{path}")
    "#{get_wringer_url_per_environment}#{path}"
  end

  def normalize_url(url)
    u = url.to_s.strip
    uri = URI.parse(u)
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    u
  end

  def safe_wringer_call
    yield
  rescue Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error "[safe_wringer_call] *** Wringer unreachable: #{e.class} - #{e.message}"
    { abort_update: true, error: "[safe_wringer_call] Wringer server unavailable: #{e.class} - #{e.message}" }
  rescue StandardError => e
    Rails.logger.error "[safe_wringer_call] *** Wringer unexpected error: #{e.class} - #{e.message}"
    { abort_update: true, error: "[safe_wringer_call] Wringer error: #{e.class} - #{e.message}" }
  end

  def wringer_received_404?(url)
    url = url.first if url.is_a?(Array)
    url = normalize_url(url)

    result = safe_wringer_call do
      stored_uri = CGI.escape(url)

      path = "/websites.json?#{URI.encode_www_form(term: stored_uri)}"
      resp = HTTParty.get("#{get_wringer_url_per_environment}#{path}")

      ok = resp.respond_to?(:code) && resp.code.to_i == 200
      next false unless ok

      data = resp.parsed_response
      next false unless data.is_a?(Array) && data.first.is_a?(Hash)

      webpage = data.first
      webpage["http_response_code"].to_i == 404 && webpage["uri"] == stored_uri
    end

    return false if result.is_a?(Hash) && result[:abort_update]
    
    !!result
  end

  def get_wringer_url_per_environment
    if Rails.env.development? || Rails.env.test?
      "http://localhost:3009"
    else
      "http://footlight-wringer.herokuapp.com"
    end
  end
end
