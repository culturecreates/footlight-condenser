module Distillator
  # One instance per comparison/run. Cache only the raw reconciliation response;
  # webpage-specific selection and self-link removal still run on each side.
  class ComparisonRefreshProxy < StatementsHelper::RefreshProxy
    LOOKUP_TIMEOUT = 10

    def initialize(**options)
      super
      @responses = {}
      @performance = { "lookups" => 0, "http_requests" => 0, "cache_hits" => 0, "http_ms" => 0.0, "errors" => 0, "error_classes" => {} }
    end

    def reconciliation_performance
      @performance.deep_dup
    end

    def reconciliation_response_for(url)
      @performance["lookups"] += 1
      if @responses.key?(url)
        @performance["cache_hits"] += 1
        return @responses.fetch(url).deep_dup
      end

      @performance["http_requests"] += 1
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        response = HTTParty.get(url, timeout: LOOKUP_TIMEOUT)
        if response.respond_to?(:code) && !response.code.to_i.between?(200, 299)
          raise "Reconciliation HTTP #{response.code}"
        end
        payload = response.respond_to?(:parsed_response) ? response.parsed_response : response
        raise "Invalid reconciliation response" unless payload.is_a?(Hash)
        # Cache valid empty results as well as hits, but never an error payload.
        raise "Reconciliation returned an error" if payload.key?("error") || payload.key?(:error)
        results = url.include?("?queries=") ? payload.dig("q0", "result") : payload["result"]
        raise "Reconciliation results missing" unless results.is_a?(Array)
        @responses[url] = payload.deep_dup
        payload.deep_dup
      rescue StandardError => error
        @performance["errors"] += 1
        @performance["error_classes"][error.class.name] = @performance["error_classes"].fetch(error.class.name, 0) + 1
        raise
      ensure
        @performance["http_ms"] = (@performance["http_ms"] + (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
      end
    end
  end
end
