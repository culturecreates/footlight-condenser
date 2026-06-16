require "digest/sha2"
require "json"

module Distillator
  class MigrationComparator
    MATCH = "MATCH".freeze
    MISSING_STATEMENT = "MISSING_STATEMENT".freeze
    EXTRA_STATEMENT = "EXTRA_STATEMENT".freeze
    DIFFERENT_VALUE = "DIFFERENT_VALUE".freeze
    PARSE_ERROR = "PARSE_ERROR".freeze

    STATEMENT_VERDICT_PRECEDENCE = [
      PARSE_ERROR,
      DIFFERENT_VALUE,
      MISSING_STATEMENT,
      EXTRA_STATEMENT
    ].freeze

    STATEMENT_METADATA_KEYS = %w[
      cache_changed
      cache_refreshed
      created_at
      debug
      duration_ms
      generatedAt
      probe
      recorded_at
      timing
      trace
      updated_at
    ].freeze

    Result = Struct.new(
      :statement_verdict,
      :statement_artifacts,
      :export_verdict,
      :export_artifacts,
      :fetch_diagnostic_verdict,
      :fetch_artifacts,
      keyword_init: true
    )

    StatementComparison = Struct.new(:verdict, :artifacts, keyword_init: true)
    ExportComparison = Struct.new(:verdict, :artifacts, keyword_init: true)
    FetchComparison = Struct.new(:verdict, :artifacts, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(
      website:,
      webpage:,
      legacy_html:,
      condenser_html:,
      legacy_fetch: nil,
      condenser_fetch: nil,
      default_language: nil,
      sources: nil,
      refresh_helper: nil,
      source_resolver: Statements::RefreshWebpageStatementsService,
      export_service: ExportArtsdataService
    )
      @website = website
      @webpage = webpage
      @legacy_html = legacy_html
      @condenser_html = condenser_html
      @legacy_fetch = legacy_fetch
      @condenser_fetch = condenser_fetch
      @default_language = default_language || website.default_language
      @sources = sources
      @refresh_helper = refresh_helper || StatementsHelper.build_refresh_proxy(cookies: {})
      @source_resolver = source_resolver
      @export_service = export_service
    end

    def call
      statement_result = compare_statements

      if statement_result.verdict == MATCH
        export_result = compare_export
        Result.new(
          statement_verdict: statement_result.verdict,
          statement_artifacts: statement_result.artifacts,
          export_verdict: export_result.verdict,
          export_artifacts: export_result.artifacts,
          fetch_diagnostic_verdict: nil,
          fetch_artifacts: nil
        )
      else
        fetch_result = compare_fetch_when_needed
        Result.new(
          statement_verdict: statement_result.verdict,
          statement_artifacts: statement_result.artifacts,
          export_verdict: nil,
          export_artifacts: nil,
          fetch_diagnostic_verdict: fetch_result&.verdict,
          fetch_artifacts: fetch_result&.artifacts
        )
      end
    end

    def compare_statements
      artifacts = resolved_sources.sort_by { |source| [source.property_id.to_i, source.id.to_i] }.map do |source|
        compare_source(source)
      end

      StatementComparison.new(
        verdict: overall_statement_verdict(artifacts),
        artifacts: artifacts
      )
    end

    def compare_export
      actual = Distillator::ExportNormalizer.normalize(export_service.call(seedurl: website.seedurl))
      expected = Distillator::ExportNormalizer.normalize(export_service.production_equivalent(seedurl: website.seedurl))

      ExportComparison.new(
        verdict: actual == expected ? MATCH : DIFFERENT_VALUE,
        artifacts: {
          actual: actual,
          expected: expected
        }
      )
    end

    def compare_fetch_when_needed
      return nil if legacy_fetch.nil? || condenser_fetch.nil?

      legacy = normalize_fetch_artifact(legacy_fetch)
      condenser = normalize_fetch_artifact(condenser_fetch)

      FetchComparison.new(
        verdict: legacy == condenser ? MATCH : DIFFERENT_VALUE,
        artifacts: {
          legacy: legacy,
          condenser: condenser
        }
      )
    end

    private

    attr_reader :website, :webpage, :legacy_html, :condenser_html, :legacy_fetch, :condenser_fetch,
                :default_language, :sources, :refresh_helper, :source_resolver, :export_service

    def resolved_sources
      explicit_sources = Array(sources).presence
      return explicit_sources if explicit_sources

      source_resolver
        .sources_for_webpage(webpage, default_language: default_language)
        .select { |source| source.selected? }
    end

    def compare_source(source)
      legacy = extract_value(source, html: legacy_html, side: :legacy)
      condenser = extract_value(source, html: condenser_html, side: :condenser)

      {
        source_id: source.id,
        property_id: source.property_id,
        property_label: source.property.label,
        language: source.language,
        legacy: legacy[:value],
        condenser: condenser[:value],
        legacy_error: normalized_error(legacy[:error]),
        condenser_error: normalized_error(condenser[:error]),
        verdict: classify_statement_verdict(legacy, condenser)
      }
    end

    def extract_value(source, html:, side:)
      if html.blank?
        return {
          value: nil,
          error: {
            error: "#{side.to_s.humanize} HTML is not available for comparison",
            error_type: "MissingComparisonHtml",
            source: "migration_comparator"
          }
        }
      end

      runner = Dsl::Core::AlgorithmRunner.new(
        url: webpage.url,
        render_js: source.render_js,
        scrape_options: refresh_helper.statement_scrape_options(
          source: source,
          webpage: webpage,
          scrape_options: { force_scrape_every_hrs: 0 }
        ),
        tracer: Dsl::Tracing::NullTracer.new
      )
      runner.instance_variable_set(:@html, html)
      runner.instance_variable_set(:@page, Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s))
      runner.define_singleton_method(:fetch_result_for) do |url:, render_js:, scrape_options:|
        {
          status: :abort,
          body: [
            "abort_update",
            {
              error: "Read-only migration comparison cannot fetch additional URLs",
              error_type: "MigrationComparatorFetchUnsupported",
              source: "migration_comparator",
              step: "url"
            }
          ],
          headers: {},
          final_url: url,
          redirect_chain: [url],
          duration_ms: 0
        }
      end

      raw = runner.run(source.algorithm_value)
      return { value: nil, error: raw.second.to_h } if abort_structure?(raw)

      formatted = refresh_helper.format_datatype(raw, source.property, webpage, statement_status: "initial")
      return { value: nil, error: formatted.second.to_h } if abort_structure?(formatted)

      normalized_value = normalize_statement_value(formatted)
      { value: blank_value?(normalized_value) ? nil : normalized_value, error: nil }
    rescue StandardError => error
      {
        value: nil,
        error: {
          error: error.message,
          error_type: error.class.to_s,
          source: "migration_comparator"
        }
      }
    end

    def overall_statement_verdict(artifacts)
      verdicts = artifacts.map { |artifact| artifact[:verdict] }.uniq
      return MATCH if verdicts == [MATCH]

      STATEMENT_VERDICT_PRECEDENCE.find { |verdict| verdicts.include?(verdict) } || DIFFERENT_VALUE
    end

    def classify_statement_verdict(legacy, condenser)
      return PARSE_ERROR if legacy[:error].present? || condenser[:error].present?
      return MATCH if normalized_statement_value_equal?(legacy[:value], condenser[:value])
      return MISSING_STATEMENT if blank_value?(condenser[:value]) && !blank_value?(legacy[:value])
      return EXTRA_STATEMENT if blank_value?(legacy[:value]) && !blank_value?(condenser[:value])

      DIFFERENT_VALUE
    end

    def normalized_statement_value_equal?(left, right)
      normalize_statement_value(left) == normalize_statement_value(right)
    end

    def normalize_statement_value(value)
      case value
      when Hash
        value
          .reject { |key, _| STATEMENT_METADATA_KEYS.include?(key.to_s) }
          .sort_by { |key, _| key.to_s }
          .each_with_object({}) do |(key, child), out|
            out[key.to_s] = normalize_statement_value(child)
          end
      when Array
        value.map { |entry| normalize_statement_value(entry) }
             .sort_by { |entry| JSON.generate(entry) }
      when String
        value.gsub(/\s+/, " ").strip
      else
        value
      end
    end

    def normalized_error(error)
      return nil unless error.respond_to?(:to_h)

      error.to_h.slice("error", "error_type", "source", "step").transform_keys(&:to_s)
    end

    def blank_value?(value)
      return true if value.blank?
      return value.all? { |entry| blank_value?(entry) } if value.is_a?(Array)
      return value.values.all? { |entry| blank_value?(entry) } if value.is_a?(Hash)

      false
    end

    def abort_structure?(value)
      value.is_a?(Array) && value.first == "abort_update" && value.second.respond_to?(:to_h)
    end

    def normalize_fetch_artifact(response)
      {
        status: response_value(response, :status).to_s,
        http_code: extract_http_code(response),
        final_url: response_value(response, :final_url).presence,
        redirect_chain: Array(response_value(response, :redirect_chain)).map(&:to_s),
        body_digest: body_digest(response_value(response, :body)),
        body_length: body_length(response_value(response, :body)),
        content_type: extract_content_type(response)
      }
    end

    def extract_http_code(response)
      response_value(response, :http_code) ||
        response_value(response, :http_response_code) ||
        nested_response_value(response, :wringer, :http_code)
    end

    def extract_content_type(response)
      headers = response_value(response, :headers)
      return unless headers.respond_to?(:[])

      headers[:content_type] ||
        headers["content_type"] ||
        headers["Content-Type"] ||
        headers[:"Content-Type"]
    end

    def body_digest(body)
      Digest::SHA256.hexdigest(serialized_body(body))
    end

    def body_length(body)
      serialized_body(body).bytesize
    end

    def serialized_body(body)
      case body
      when Hash, Array
        JSON.generate(body)
      else
        body.to_s
      end
    end

    def response_value(response, key)
      response[key] || response[key.to_s]
    end

    def nested_response_value(response, parent_key, child_key)
      parent = response_value(response, parent_key)
      return unless parent.respond_to?(:[])

      parent[child_key] || parent[child_key.to_s]
    end
  end
end
