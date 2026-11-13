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
      comparison = Distillator::MigrationComparator.new(website: webpage.website, webpage: webpage,
        legacy_html: legacy_html, condenser_html: condenser_html, sources: source_list, refresh_helper: refresh_helper).compare_statements
      groups_by_verdict = {
        "MATCH" => :same, "EXTRA_STATEMENT" => :added, "MISSING_STATEMENT" => :removed,
        "DIFFERENT_VALUE" => :changed, "PARSE_ERROR" => :extraction_errors
      }
      rows = comparison.artifacts.map do |artifact|
        artifact.merge(group: groups_by_verdict.fetch(artifact[:verdict]),
          statement_id: Statement.find_by(webpage_id: webpage.id, source_id: artifact[:source_id])&.id,
          source_label: "#{artifact[:property_label]} (source ##{artifact[:source_id]})")
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

    def normalized_property_ids(property_ids)
      ids = Array(property_ids).filter_map do |value|
        integer = value.to_i
        integer if integer.positive?
      end
      ids.presence || DEFAULT_PROPERTY_IDS
    end
  end
end
