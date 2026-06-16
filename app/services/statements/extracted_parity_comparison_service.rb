module Statements
  class ExtractedParityComparisonService
    DEFAULT_PROPERTY_IDS = [1, 3, 5, 13].freeze

    Result = Struct.new(
      :url,
      :webpage,
      :property_ids,
      :legacy_html_present,
      :condenser_html_present,
      :sources_count,
      :groups,
      :counts,
      keyword_init: true
    )

    def self.call(**kwargs)
      init_kwargs = kwargs.slice(:refresh_helper, :source_resolver)
      call_kwargs = kwargs.except(:refresh_helper, :source_resolver)
      new(**init_kwargs).call(**call_kwargs)
    end

    def initialize(refresh_helper: nil, source_resolver: Statements::RefreshWebpageStatementsService)
      @refresh_helper = refresh_helper || StatementsHelper.build_refresh_proxy(cookies: {})
      @source_resolver = source_resolver
    end

    def call(webpage:, default_language: "en", legacy_html:, condenser_html:, sources: nil, property_ids: DEFAULT_PROPERTY_IDS)
      scoped_property_ids = normalized_property_ids(property_ids)
      source_list = Array(sources).presence || source_resolver.sources_for_webpage(
        webpage,
        default_language: default_language,
        property_ids: scoped_property_ids
      )
      rows = source_list.sort_by { |source| [source.property_id.to_i, source.id.to_i] }.map do |source|
        compare_source(source, webpage, legacy_html: legacy_html, condenser_html: condenser_html)
      end
      groups = rows.group_by { |row| row[:group] }

      Result.new(
        url: webpage.url,
        webpage: webpage,
        property_ids: scoped_property_ids,
        legacy_html_present: legacy_html.present?,
        condenser_html_present: condenser_html.present?,
        sources_count: source_list.count,
        groups: {
          same: groups.fetch(:same, []),
          added: groups.fetch(:added, []),
          removed: groups.fetch(:removed, []),
          changed: groups.fetch(:changed, []),
          extraction_errors: groups.fetch(:extraction_errors, [])
        },
        counts: {
          same: groups.fetch(:same, []).count,
          added: groups.fetch(:added, []).count,
          removed: groups.fetch(:removed, []).count,
          changed: groups.fetch(:changed, []).count,
          extraction_errors: groups.fetch(:extraction_errors, []).count
        }
      )
    end

    private

    attr_reader :refresh_helper, :source_resolver

    def compare_source(source, webpage, legacy_html:, condenser_html:)
      legacy = extract_value(source, webpage, html: legacy_html, side: :legacy)
      condenser = extract_value(source, webpage, html: condenser_html, side: :condenser)

      {
        source_id: source.id,
        statement_id: Statement.find_by(webpage_id: webpage.id, source_id: source.id)&.id,
        property_label: source.property.label,
        source_label: source_label(source),
        legacy: legacy[:value],
        condenser: condenser[:value],
        legacy_error: legacy[:error],
        condenser_error: condenser[:error],
        group: classify_group(legacy, condenser)
      }
    end

    def extract_value(source, webpage, html:, side:)
      if html.blank?
        return {
          value: nil,
          error: {
            error: "#{side.to_s.humanize} HTML is not available for comparison",
            error_type: "MissingComparisonHtml",
            source: "statement_parity_compare"
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
              error: "Read-only statement parity comparison cannot fetch additional URLs",
              error_type: "StatementParityFetchUnsupported",
              source: "statement_parity_compare",
              step: "url"
            }
          ],
          headers: {},
          final_url: url,
          redirect_chain: [url],
          wringer: {
            error_type: "StatementParityFetchUnsupported",
            source: "statement_parity_compare",
            signals: {},
            hints: ["read_only_compare"],
            final_url: url,
            redirect_chain: [url]
          },
          duration_ms: 0
        }
      end

      raw = runner.run(source.algorithm_value)
      return { value: nil, error: raw.second.to_h } if abort_structure?(raw)

      formatted = refresh_helper.format_datatype(raw, source.property, webpage, statement_status: "initial")
      return { value: nil, error: formatted.second.to_h } if abort_structure?(formatted)

      value = blank_value?(formatted) ? nil : formatted
      { value: value, error: nil }
    rescue StandardError => error
      {
        value: nil,
        error: {
          error: error.message,
          error_type: error.class.to_s,
          source: "statement_parity_compare"
        }
      }
    end

    def classify_group(legacy, condenser)
      return :extraction_errors if legacy[:error].present? || condenser[:error].present?
      return :same if values_equal?(legacy[:value], condenser[:value])
      return :added if blank_value?(legacy[:value]) && present_value?(condenser[:value])
      return :removed if present_value?(legacy[:value]) && blank_value?(condenser[:value])

      :changed
    end

    def values_equal?(left, right)
      normalize_value(left) == normalize_value(right)
    end

    def normalize_value(value)
      case value
      when Array
        value.map { |entry| normalize_value(entry) }
      when Hash
        value.transform_values { |entry| normalize_value(entry) }
      else
        value
      end
    end

    def blank_value?(value)
      return true if value.blank?
      return value.all? { |entry| blank_value?(entry) } if value.is_a?(Array)
      return value.values.all? { |entry| blank_value?(entry) } if value.is_a?(Hash)

      false
    end

    def present_value?(value)
      !blank_value?(value)
    end

    def abort_structure?(value)
      value.is_a?(Array) && value.first == "abort_update" && value.second.respond_to?(:to_h)
    end

    def source_label(source)
      "#{source.property.label} (source ##{source.id})"
    end

    def normalized_property_ids(property_ids)
      ids = Array(property_ids).filter_map do |value|
        integer = value.to_i
        integer if integer.positive?
      end
      ids.presence || DEFAULT_PROPERTY_IDS
    end
  end
end
