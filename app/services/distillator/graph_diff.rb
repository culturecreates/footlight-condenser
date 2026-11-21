require "json"

module Distillator
  class GraphDiff
    Result = Struct.new(
      :added,
      :removed,
      :same_count,
      :added_count,
      :removed_count,
      :changed_literal_values,
      :changed_uri_objects,
      keyword_init: true
    ) do
      def to_h
        {
          added: added,
          removed: removed,
          same_count: same_count,
          added_count: added_count,
          removed_count: removed_count,
          changed_literal_values: changed_literal_values,
          changed_uri_objects: changed_uri_objects
        }
      end
    end

    def self.call(expected_graph:, actual_graph:)
      new(expected_graph: expected_graph, actual_graph: actual_graph).call
    end

    def initialize(expected_graph:, actual_graph:)
      @expected_graph = coerce_graph(expected_graph)
      @actual_graph = coerce_graph(actual_graph)
    end

    def call
      expected_lines = statement_lines(expected_graph)
      actual_lines = statement_lines(actual_graph)

      added = actual_lines - expected_lines
      removed = expected_lines - actual_lines
      same = expected_lines & actual_lines

      Result.new(
        added: added,
        removed: removed,
        same_count: same.count,
        added_count: added.count,
        removed_count: removed.count,
        changed_literal_values: changed_objects(expected_graph, actual_graph, literal_only: true),
        changed_uri_objects: changed_objects(expected_graph, actual_graph, uri_only: true)
      )
    end

    private

    attr_reader :expected_graph, :actual_graph

    def coerce_graph(value)
      return value if value.is_a?(RDF::Graph)

      string = value.to_s
      return load_jsonld_graph(string) if json?(string)

      RDF::Graph.new << RDF::Reader.for(:nquads).new(string)
    end

    def load_jsonld_graph(string)
      RDF::Graph.new << JSON::LD::API.toRdf(JSON.parse(string))
    end

    def json?(string)
      JSON.parse(string)
      true
    rescue JSON::ParserError
      false
    end

    def statement_lines(graph)
      graph.statements.map { |statement| statement.to_ntriples.strip }.sort
    end

    def changed_objects(left_graph, right_graph, literal_only: false, uri_only: false)
      left_index = index_by_subject_predicate(left_graph)
      right_index = index_by_subject_predicate(right_graph)

      (left_index.keys & right_index.keys).sort.map do |key|
        left_objects = left_index[key]
        right_objects = right_index[key]
        next if left_objects == right_objects

        changed = {
          subject: key[0],
          predicate: key[1],
          expected: left_objects,
          actual: right_objects
        }

        next if literal_only && !(left_objects + right_objects).all? { |obj| obj.start_with?("\"") }
        next if uri_only && !(left_objects + right_objects).all? { |obj| obj.start_with?("<") }

        changed
      end.compact
    end

    def index_by_subject_predicate(graph)
      graph.statements.each_with_object({}) do |statement, index|
        key = [statement.subject.to_ntriples.strip, statement.predicate.to_ntriples.strip]
        index[key] ||= []
        index[key] << statement.object.to_ntriples.strip
        index[key].sort!
      end
    end
  end
end
