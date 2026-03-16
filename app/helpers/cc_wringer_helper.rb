#app/helpers/cc_wringer_helper.rb
require "uri"

# Helper methods for interacting with the Footlight Wringer service.
#
# Key design choices in this module:
# - `use_wringer` *builds* a wringer URL for later use (e.g., by a scraper / pipeline), and does NOT make a network request.
# - `wringer_received_404?` *does* call Wringer to determine whether Wringer stored a 404.
# - `safe_wringer_call` is a small guard wrapper that turns network errors into a structured `{ abort_update: true, error: "..." }` response so callers can short-circuit gracefully.
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
    url = normalize_url(url)                                                # Normalize URL to a string: remove fragments and sanitize

    query = {                                                               # Build query string for Wringer
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

  # Normalize an input URL string.
  #
  # Purpose:
  # - Convert to string, strip whitespace.
  # - Parse via URI and remove fragment identifiers (e.g., `#section`),
  #   which are irrelevant to remote fetches and can cause duplication.
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
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    u
  end

  # Execute a block that may perform network I/O to Wringer, and convert failures into a structured "abort" response.
  #
  # Purpose:
  # - Prevent transient Wringer failures from crashing the calling controller/job.
  # - Provide a consistent return shape on failure:
  #   `{ abort_update: true, error: "..." }`
  #
  # Usage:
  #   result = safe_wringer_call { HTTParty.get(...) }
  #   return result if result[:abort_update]
  #
  # Returns:
  # - On success: returns the block value.
  # - On failure: returns Hash with abort info.
  #
  # Catches:
  # - Connection refused, DNS errors, open/read timeouts
  # - Any other StandardError as "unexpected"
  def safe_wringer_call
    yield
  rescue Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error "[safe_wringer_call] *** Wringer unreachable: #{e.class} - #{e.message}"
    ["abort_update", { error: "Wringer unreachable: #{e.class} - #{e.message}", error_type: e.class.to_s }]
  rescue StandardError => e
    Rails.logger.error "[safe_wringer_call] *** Wringer unexpected error: #{e.class} - #{e.message}"
    ["abort_update", { error: "Wringer error: #{e.class} - #{e.message}", error_type: e.class.to_s }]
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
    url = normalize_url(url)

    result = safe_wringer_call do
      stored_uri = CGI.escape(url)

      path = "/websites.json?#{URI.encode_www_form(term: stored_uri)}"
      resp = HTTParty.get("#{get_wringer_url_per_environment}#{path}")

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
    return false if result.is_a?(Hash) && result[:abort_update]
    
    !!result                                                         # Return true if we found a 404 for the URL. Otherwise, false.
  end

  def get_wringer_url_per_environment
    if Rails.env.development? || Rails.env.test?
      "http://localhost:3009"
    else
      "http://footlight-wringer.herokuapp.com"
    end
  end
end
