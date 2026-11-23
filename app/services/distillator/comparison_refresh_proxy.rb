require "digest"

module Distillator
  # Cache raw responses so webpage-specific selection and self-link removal
  # still run on each side. Failed lookups are shared only within one source pair.
  class ComparisonRefreshProxy < StatementsHelper::RefreshProxy
    LOOKUP_TIMEOUT = 10
    COUNTERS = %w[lookups http_requests cache_hits failure_reuses retried_lookups http_ms failed_http_ms errors].freeze

    class HTTPError < RuntimeError
      attr_reader :status

      def initialize(status)
        @status = status.to_i
        super("Reconciliation HTTP #{@status}")
      end
    end

    class InvalidResponse < RuntimeError; end

    def initialize(response_file: nil, **options)
      super(**options)
      @responses = {}
      @failed_requests = {}
      @response_file = response_file
      @performance = new_counters.merge("error_classes" => {}, "http_error_statuses" => {}, "by_type" => {}, "by_source" => {})
    end

    def with_reconciliation_pair(source)
      previous_pair = @pair
      @pair = { source_id: source.id.to_s, failures: {} }
      yield
    ensure
      @pair = previous_pair
    end

    def format_datatype(...)
      return super unless @pair

      previous_failure = @formatting_failure
      @formatting_failure = nil
      result = super
      return result unless @formatting_failure

      error = @formatting_failure
      reason = error.is_a?(HTTPError) ? "HTTP #{error.status}" : error.class.name
      ["abort_update", { error: "Artsdata reconciliation did not complete (#{reason}).",
        error_type: "LinkedDataLookupError", source: "comparison_reconciliation" }]
    ensure
      @formatting_failure = previous_failure if @pair
    end

    def reconciliation_performance
      @performance.deep_dup
    end

    def reconciliation_response_for(url)
      counters = lookup_counters(url)
      increment(counters, "lookups")
      key = Digest::SHA256.digest(url)
      if (stored = @responses[key])
        increment(counters, "cache_hits")
        return stored.deep_dup unless @response_file

        offset, bytes = stored
        return JSON.parse(@response_file.pread(bytes, offset))
      end
      if (error = @pair&.dig(:failures, key))
        increment(counters, "failure_reuses")
        @formatting_failure ||= error
        raise error
      end

      request_response(url, key, counters)
    end

    private

    def request_response(url, key, counters)
      increment(counters, "http_requests")
      increment(counters, "retried_lookups") if @failed_requests.key?(key)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = HTTParty.get(url, timeout: LOOKUP_TIMEOUT)
      payload = checked_payload(response, url)
      store_response(key, payload)
      @failed_requests.delete(key)
      payload
    rescue StandardError => error
      failed = true
      @failed_requests[key] = true
      @pair[:failures][key] = error if @pair
      @formatting_failure ||= error if @pair
      increment(counters, "errors")
      count_error("error_classes", error.class.name)
      count_error("http_error_statuses", error.status.to_s) if error.is_a?(HTTPError)
      raise
    ensure
      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
      increment(counters, "http_ms", duration)
      increment(counters, "failed_http_ms", duration) if failed
    end

    def checked_payload(response, url)
      if response.respond_to?(:code) && !response.code.to_i.between?(200, 299)
        raise HTTPError, response.code
      end
      payload = response.respond_to?(:parsed_response) ? response.parsed_response : response
      raise InvalidResponse, "Invalid reconciliation response" unless payload.is_a?(Hash)

      entry = url.include?("?queries=") ? payload["q0"] : payload
      if [payload, entry].any? { |data| data.is_a?(Hash) && (data.key?("error") || data.key?(:error)) }
        raise InvalidResponse, "Reconciliation returned an error"
      end
      raise InvalidResponse, "Reconciliation results missing" unless entry.is_a?(Hash) && entry["result"].is_a?(Array)

      payload
    end

    def store_response(key, payload)
      if @response_file
        encoded = JSON.generate(payload)
        offset = @response_file.pos
        @response_file.write(encoded)
        @response_file.flush
        @responses[key] = [offset, encoded.bytesize]
      else
        @responses[key] = payload.deep_dup
      end
    end

    def lookup_counters(url)
      type = lookup_type(url)
      counters = [@performance, @performance["by_type"][type] ||= new_counters]
      counters << (@performance["by_source"][@pair[:source_id]] ||= new_counters) if @pair
      counters
    end

    def lookup_type(url)
      params = CGI.parse(url.partition("?").last)
      type = params["type"].first
      type ||= JSON.parse(params["queries"].first).dig("q0", "type") if params["queries"].present?
      type.presence || "Unknown"
    rescue JSON::ParserError, TypeError
      "Unknown"
    end

    def new_counters
      COUNTERS.index_with(0)
    end

    def increment(counters, key, amount = 1)
      counters.each { |row| row[key] += amount }
    end

    def count_error(group, key)
      counts = @performance.fetch(group)
      counts[key] = counts.fetch(key, 0) + 1
    end
  end
end
