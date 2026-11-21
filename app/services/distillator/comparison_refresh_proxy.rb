require "digest"

module Distillator
  # One instance per comparison/run. Cache only the raw reconciliation response;
  # webpage-specific selection and self-link removal still run on each side.
  class ComparisonRefreshProxy < StatementsHelper::RefreshProxy
    LOOKUP_TIMEOUT = 10

    def initialize(response_file: nil, **options)
      super(**options)
      @responses = {}
      @response_file = response_file
      @performance = { "lookups" => 0, "http_requests" => 0, "cache_hits" => 0, "http_ms" => 0.0, "errors" => 0, "error_classes" => {} }
    end

    def reconciliation_performance
      @performance.deep_dup
    end

    def reconciliation_response_for(url)
      @performance["lookups"] += 1
      # A digest keeps large reconciliation query strings out of the run's index.
      key = @response_file ? Digest::SHA256.digest(url) : url
      if (stored = @responses[key])
        @performance["cache_hits"] += 1
        return stored.deep_dup unless @response_file

        offset, bytes = stored
        return JSON.parse(@response_file.pread(bytes, offset))
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
        if @response_file
          encoded = JSON.generate(payload)
          offset = @response_file.pos
          @response_file.write(encoded)
          @response_file.flush
          @responses[key] = [offset, encoded.bytesize]
        else
          @responses[key] = payload.deep_dup
        end
        payload
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
