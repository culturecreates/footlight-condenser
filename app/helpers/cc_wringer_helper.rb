#app/helpers/cc_wringer_helper.rb
require "uri"

# Helper methods for interacting with the Footlight Wringer service.
#
# Key design choices in this module:
# - `use_wringer` *builds* a wringer URL for later use (e.g., by a scraper / pipeline), and does NOT make a network request.
# - `wringer_received_404?` *does* call Wringer to determine whether Wringer stored a 404.
# - `safe_wringer_call` is a small guard wrapper that turns network errors into
#   `["abort_update", { error: "...", error_type: "..." }]` so callers can short-circuit gracefully.
#   
# Architecture:
#
#     Wringer response
#            ↓ 
#      Normalization
#            ↓
#    Rule engine (YAML)
#            ↓
#     Policy extraction
#            ↓
#      Action dispatch
#            ↓
#    DSL / Sidekiq reacts
#    
module CcWringerHelper
  # Build a Wringer "wring" URL for a given target URL.
  #
  # Purpose:
  # - Normalize and sanitize the input URL (strip whitespace, remove fragment).
  # - Build a query string for Wringer's `/websites/wring` endpoint.
  # - Return the full URL as a STRING.
  #
  # Parameters:
  # - url: String | Array
  #   If an Array is provided (legacy/caller behavior), the first element is used.
  # - render_js: Boolean
  #   If true, adds `use_phantomjs=true` to request server-side rendering.
  # - options: Hash
  #   Supported options:
  #   - :force_scrape_every_hrs (Integer|String|nil): if present, instruct wringer to re-scrape.
  #   - :json_post (Boolean): if true, adds `json_post=true` (used by some pipelines).
  #
  # Returns:
  # - String: fully-qualified Wringer URL (base + path + query).
  #
  # Side effects:
  # - Logs the URL it generated (info level).
  #
  # Error behavior:
  # - If URL parsing fails, `normalize_url` falls back to a stripped string.
  def use_wringer(url, render_js = false, options = {})
    defaults = { force_scrape_every_hrs: nil }
    options = defaults.merge(options)
    url = url.first if url.is_a?(Array)                                     # Some callers pass arrays; preserve compatibility.
    url = wringer_uri_target(url)                                           # Preserve fragment semantics for Wringer-compatible URI keys.

    query = {                                                               # Build query string for Wringer
      uri: url,
      format: "raw",
      include_fragment: "true"
    }
    query[:use_phantomjs] = "true" if render_js
    query[:force_scrape_every_hrs] = options[:force_scrape_every_hrs] if options[:force_scrape_every_hrs]
    query[:json_post] = "true" if options[:json_post]

    path = "/websites/wring?#{URI.encode_www_form(query)}"
    base_url = legacy_wringer_fallback_requested?(options) ? legacy_wringer_base_url : distillator_compatibility_base_url
    raise ArgumentError, "Wringer compatibility endpoint is not configured" if base_url.blank?

    if legacy_wringer_fallback_requested?(options)
      logger.warn("[Wringer] deprecated legacy fallback url=#{base_url}#{path}")
    else
      logger.info("*** calling distillator compatibility endpoint with: #{base_url}#{path}")
    end

    "#{base_url}#{path}"
  end

  # Normalize an input URL string.
  #
  # Purpose:
  # - Convert to string, strip whitespace.
  # - Parse via URI and preserve fragment identifiers so Wringer-compatible
  #   callers can still decide whether `include_fragment` should affect the key.
  #
  # Parameters:
  # - url: String (or anything responding to `to_s`)
  #
  # Returns:
  # - String: normalized URL.
  #
  # Error behavior:
  # - If URI parsing fails (invalid URI), returns the stripped string as-is.
  def normalize_url(url)
    u = url.to_s.strip
    uri = URI.parse(u)
    uri.to_s
  rescue URI::InvalidURIError
    u
  end

  def normalized_fetch_url(url)
    normalized = normalize_url(url)
    uri = URI.parse(normalized)
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    normalized.to_s.split("#").first
  end

  def wringer_uri_target(url)
    normalize_url(url)
  end

  # Execute a block that may perform network I/O to Wringer, and convert failures into a structured "abort" response.
  #
  # Purpose:
  # - Prevent transient Wringer failures from crashing the calling controller/job.
  # - Provide a consistent return shape on failure:
  #   `["abort_update", { error: "...", error_type: "..." }]`
  #
  # Usage:
  #   result = safe_wringer_call { HTTParty.get(...) }
  #   return result if result.is_a?(Array) && result.first == "abort_update"
  #
  # Returns:
  # - On success: returns the block value.
  # - On failure: returns a two-element Array with abort info.
  #
  # Catches:
  # - Connection refused, DNS errors, open/read timeouts
  # - Any other StandardError as "unexpected"
  def safe_wringer_call(normalize_response: false)
    resp = yield

    response =
      if resp.respond_to?(:code) && resp.respond_to?(:body)
        {
          body: resp.body,
          http_code: resp.code,
          final_url: resp.respond_to?(:uri) ? resp.uri.to_s : nil
        }
      else
        { body: resp, http_code: 200, final_url: nil }
      end

    if (err = wringer_system_error?(response))
      policy = err[:policy] || {}
      action = policy["action"] || policy[:action] || "abort_update"

      Rails.logger.error "[Wringer] #{err[:error_type]} (action=#{action})"

      err[:action] = action
      err[:retry] = policy.key?("retry") ? policy["retry"] : policy[:retry]
      err[:cache] = policy.key?("cache") ? policy["cache"] : policy[:cache]
      err[:delete] = policy.key?("delete") ? policy["delete"] : policy[:delete]
      
      return [action, err]
    end

    normalize_response ? response : response[:body]
  rescue Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error "[Wringer] unreachable: #{e.class} - #{e.message}"

    ["abort_update", {
      error: e.message,
      error_type: "wringer_unreachable",
      policy: {
        retry: true,     # 👈 retry later
        cache: false     # 👈 force refresh next time
      },
      source: "wringer"
    }]
  rescue StandardError => e
    Rails.logger.error "[Wringer] unexpected error: #{e.class} - #{e.message}"

    ["abort_update", {
      error: e.message,
      error_type: "wringer_error",
      policy: {
        retry: true,     # 👈 usually safe to retry
        cache: false
      },
      source: "wringer"
    }]
  end


  # Ask Wringer whether it has stored an HTTP 404 result for a given URL.
  #
  # Purpose:
  # - Query Wringer's `/websites.json?term=...` endpoint to find the stored webpage record.
  # - Return true only when:
  #   - Wringer returns 200
  #   - Body is an Array with a Hash first element
  #   - The stored record matches the escaped URI
  #   - http_response_code == 404
  #
  # Parameters:
  # - url: String | Array
  #
  # Returns:
  # - Boolean:
  #   - true: Wringer has a stored 404 for that URL
  #   - false: otherwise, including when Wringer is unreachable (gracefully handled)
  #
  # Notes:
  # - `CGI.escape` is used because Wringer stores URIs escaped in this endpoint (e.g., `http://example.com/foo%20bar`).
  # - This method *performs a network request*.
  def wringer_received_404?(url)
    url = url.first if url.is_a?(Array)
    url = wringer_uri_target(url)

    unless legacy_wringer_fallback_requested?
      key = Distillator::WringerUrlKey.call(url, include_fragment: true).uri_key
      cache = Distillator::FetchCache.find_by(uri_key: key)
      return false unless cache

      return cache.http_response_code.to_i == 404
    end

    result = safe_wringer_call do
      stored_uri = CGI.escape(url)

      path = "/websites.json?#{URI.encode_www_form(term: stored_uri)}"
      legacy_url = "#{legacy_wringer_base_url}#{path}"
      Rails.logger.warn("[Wringer] deprecated legacy fallback url=#{legacy_url}")
      resp = HTTParty.get(legacy_url)

      ok = resp.respond_to?(:code) && resp.code.to_i == 200
      next false unless ok

      data = resp.parsed_response
      next false unless data.is_a?(Array) && data.first.is_a?(Hash)

      # implicit assumptions that:                                                                                                                                    # rubocop:disable Layout/CommentIndentation                            
        #  HTTParty.get(...) succeeds
        #  it returns JSON
        #  JSON parses to an Array
        #  Array is non-empty
        #  First element is a Hash
        #  Hash has expected keys                                                                                                                                     # rubocop:disable Layout/CommentIndentation

      #  Any violation → nil["http_response_code"] → NoMethodError: undefined method [] for nil:NilClass
      #  Sidekiq retries → retry storm 
      webpage = data.first

      # Strict match:
      # - stored 404
      # - stored uri equals the escaped one we queried for
      webpage["http_response_code"].to_i == 404 && webpage["uri"] == stored_uri
    end

    # If Wringer was unreachable / errored, treat as "unknown" -> false.
    return false if result.is_a?(Array) && result.first == "abort_update"
    
    !!result                                                         # Return true if we found a 404 for the URL. Otherwise, false.
  end

  def wringer_rules
    Distillator::WringerRules.all
  end

  def wringer_system_error?(response)
    return nil if response.blank?

    issue = Distillator::WringerIssueSet.call(
      body: response[:body],
      http_code: response[:http_code],
      final_url: response[:final_url],
      hints: response[:hints] || [],
      signals: response[:signals] || {},
      rules: wringer_rules
    ).primary

    issue&.slice(:error, :error_type, :policy)
  end

  def get_wringer_url_per_environment
    current_wringer_endpoint.legacy_lookup_base_url
  end

  def distillator_compatibility_base_url
    current_wringer_endpoint.compatibility_base_url
  end

  def legacy_wringer_base_url
    current_wringer_endpoint.legacy_lookup_base_url
  end

  def legacy_wringer_fallback_requested?(options = {})
    Distillator::BooleanParam.parse(
      options[:force_legacy] ||
      options["force_legacy"] ||
      ENV["DISTILLATOR_LEGACY_WRINGER_FALLBACK"]
    )
  end

  def get_legacy_wringer_url_per_environment
    current_wringer_endpoint.legacy_lookup_base_url
  end

  def current_wringer_endpoint(last_error: nil)
    Distillator::WringerEndpoint.current(last_error: last_error)
  end
end
