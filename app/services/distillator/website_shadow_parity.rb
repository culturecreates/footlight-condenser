# frozen_string_literal: true

require "json"

module Distillator
  # Exact final-state comparison between independent Danse Danse database copies.
  # No writes and no HTTP. Changes in selected statement values remain visible
  # even if the export graph stays unchanged (e.g., unpublishable events).
  class WebsiteShadowParity
    Result = Struct.new(:status, :differences, :graph_diff, keyword_init: true) do
      def passed?
        status == "passed"
      end
    end

    TRACKED = %w[website event_sources webpages statements].freeze
    MAX_EXAMPLES = 20

    def self.call(baseline:, shadow:)
      new(baseline: baseline, shadow: shadow).call
    end

    def initialize(baseline:, shadow:)
      @baseline, @shadow = baseline, shadow
    end

    def call
      raise ArgumentError, "Snapshot schema mismatch" unless @baseline.fetch("schema_version") == @shadow.fetch("schema_version")

      differences = TRACKED.each_with_object({}) do |field, result|
        before = @baseline.fetch(field)
        after = @shadow.fetch(field)
        if before.is_a?(Array) && after.is_a?(Array)
          before = before.sort_by { |row| JSON.generate(row) }
          after = after.sort_by { |row| JSON.generate(row) }
        end
        next if before == after

        if before.is_a?(Array) && after.is_a?(Array)
          removed, added = before - after, after - before
          result[field] = { removed_count: removed.size, added_count: added.size,
            removed: removed.first(MAX_EXAMPLES), added: added.first(MAX_EXAMPLES) }
        else
          result[field] = { before: before, after: after }
        end
      end

      graph_diff = Distillator::GraphDiff.call(
        expected_graph: @baseline.fetch("export_jsonld"), actual_graph: @shadow.fetch("export_jsonld")
      )
      if graph_diff.added_count.positive? || graph_diff.removed_count.positive?
        differences["artsdata_graph"] = {
          added_count: graph_diff.added_count, removed_count: graph_diff.removed_count,
          added: graph_diff.added.first(MAX_EXAMPLES), removed: graph_diff.removed.first(MAX_EXAMPLES)
        }
      end
      Result.new(status: differences.empty? ? "passed" : "failed", differences: differences, graph_diff: graph_diff)
    end
  end
end
