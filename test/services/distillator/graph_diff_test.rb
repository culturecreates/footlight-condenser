require "test_helper"

class Distillator::GraphDiffTest < ActiveSupport::TestCase
  test "returns deterministic added and removed triples" do
    expected = RDF::Graph.new
    expected << [RDF::URI("http://example.org/event"), RDF::Vocab::SCHEMA.name, RDF::Literal("Old Title")]
    expected << [RDF::URI("http://example.org/event"), RDF::Vocab::SCHEMA.location, RDF::URI("http://example.org/place")]

    actual = RDF::Graph.new
    actual << [RDF::URI("http://example.org/event"), RDF::Vocab::SCHEMA.name, RDF::Literal("New Title")]
    actual << [RDF::URI("http://example.org/event"), RDF::Vocab::SCHEMA.location, RDF::URI("http://example.org/virtual-place")]

    diff = Distillator::GraphDiff.call(expected_graph: expected, actual_graph: actual)

    assert_equal 2, diff.added_count
    assert_equal 2, diff.removed_count
    assert_equal 0, diff.same_count
    assert_equal(
      [{
        subject: "<http://example.org/event>",
        predicate: "<http://schema.org/name>",
        expected: ['"Old Title"'],
        actual: ['"New Title"']
      }],
      diff.changed_literal_values
    )
    assert_equal(
      [{
        subject: "<http://example.org/event>",
        predicate: "<http://schema.org/location>",
        expected: ["<http://example.org/place>"],
        actual: ["<http://example.org/virtual-place>"]
      }],
      diff.changed_uri_objects
    )
  end
end
