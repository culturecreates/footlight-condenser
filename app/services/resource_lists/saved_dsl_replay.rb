# frozen_string_literal: true

require "digest"
require "json"
require "uri"
require_relative "numbered_page_query"

module ResourceLists
  # Offline QA of saved numbered pages, using a caller-supplied *existing DSL*
  # executor. Never fetches pages, writes statements or claims migration parity.
  class SavedDslReplay
    Result = Struct.new(:status, :errors, :pages, :terminal_page, :total_values,
      :duplicate_values, keyword_init: true)

    def self.call(directory:, algorithm:, run_dsl:)
      new(directory:, algorithm:, run_dsl:).call
    end

    def initialize(directory:, algorithm:, run_dsl:)
      @directory, @algorithm, @run_dsl = directory, algorithm, run_dsl
    end

    def call
      probe = JSON.parse(File.binread(File.join(@directory, "probe.json")))
      audit = JSON.parse(File.binread(File.join(@directory, "semantic-next-audit.json")))
      captures = probe.fetch("captures")
      observations = audit.fetch("captures")
      return fail_result("missing_or_mismatched_capture_rows") unless captures.is_a?(Array) &&
        captures.any? && observations.is_a?(Array) && captures.length == observations.length
      query = NumberedPageQuery.new(start_url: captures.first.fetch("url"), parameter: probe.fetch("page_parameter"))
      return fail_result("invalid_algorithm") unless @algorithm.is_a?(String) && !@algorithm.strip.empty?

      pages = []
      seen = Hash.new(0)
      terminal_page = nil
      captures.each_with_index do |capture, index|
        number = Integer(capture.fetch("page"))
        url = capture.fetch("final_url")
        expected = query.first_page + index
        return fail_result("broken_page_sequence:#{number}", pages:) unless number == expected &&
          query.matches_page?(url, page: number) && query.matches_page?(capture.fetch("url"), page: number)
        row = observations[index]
        return fail_result("mismatched_semantic_audit:#{number}", pages:) unless
          row.fetch("page") == number && row.fetch("url") == url
        return fail_result("unexpected_http_status:#{number}", pages:) unless capture.fetch("status") == 200
        html = File.binread(File.join(@directory, "page#{number}.html"))
        return fail_result("snapshot_sha_mismatch:#{number}", pages:) unless
          Digest::SHA256.hexdigest(html) == capture.fetch("sha256")

        status = row.fetch("status")
        if status == "labeled_forward_observed"
          return fail_result("broken_semantic_next_chain:#{number}", pages:) if
            index == captures.length - 1 || !query.matches_page?(row.fetch("labeled_next_url"), page: number + 1) ||
            !query.matches_page?(captures[index + 1].fetch("url"), page: number + 1)
        elsif status == "no_forward_observed"
          terminal_page = number
        else
          return fail_result("inconclusive_semantic_next:#{number}:#{status}", pages:)
        end
        result = @run_dsl.call(algorithm: @algorithm, url:, html:)
        if result.is_a?(Array) && result.first == "abort_update" && result.size == 2 && result.last.is_a?(Hash)
          return fail_result("dsl_abort:#{number}:#{result.last['error_type'] || result.last[:error_type]}", pages:)
        end
        return fail_result("unexpected_dsl_output_shape:#{number}", pages:) unless result.is_a?(Array)
        return fail_result("empty_dsl_page:#{number}", pages:) if result.empty?

        fingerprint = Digest::SHA256.hexdigest(JSON.generate(result))
        result.each { |value| seen[JSON.generate(value)] += 1 }
        pages << { page: number, url:, count: result.length, sha256: fingerprint, values: result }
        break if terminal_page
      end
      return fail_result("terminal_not_observed", pages:) unless terminal_page

      Result.new(status: "dsl_replayed_parity_unverified", errors: [], pages:,
        terminal_page:, total_values: pages.sum { |p| p[:count] },
        duplicate_values: seen.values.sum { |n| n > 1 ? n - 1 : 0 })
    rescue Errno::ENOENT, JSON::ParserError, KeyError, ArgumentError, TypeError, URI::InvalidURIError => error
      fail_result("invalid_saved_evidence:#{error.class}")
    end

    private

    def fail_result(reason, pages: [])
      Result.new(status: "inconclusive", errors: [reason], pages:, terminal_page: nil,
        total_values: pages.sum { |page| page[:count] }, duplicate_values: nil)
    end
  end
end
