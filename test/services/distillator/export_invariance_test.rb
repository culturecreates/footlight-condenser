require "test_helper"

class Distillator::ExportInvarianceTest < ActiveSupport::TestCase
  FIXTURE_SEEDURL = "distillator-fixture-pack".freeze
  EXPECTED_JSONLD = Rails.root.join("test/fixtures/files/distillator_export/expected_distillator_fixture_pack.jsonld")
  EXPECTED_NQ = Rails.root.join("test/fixtures/files/distillator_export/expected_distillator_fixture_pack.nq")

  test "fixture pack export matches golden jsonld and nq graphs" do
    actual_jsonld = ExportArtsdataService.call(seedurl: FIXTURE_SEEDURL)
    actual_graph = jsonld_to_graph(actual_jsonld)
    expected_graph = jsonld_to_graph(File.read(EXPECTED_JSONLD))
    diff = Distillator::GraphDiff.call(expected_graph: expected_graph, actual_graph: actual_graph)

    assert_equal 0, diff.added_count, diff_message(diff)
    assert_equal 0, diff.removed_count, diff_message(diff)
    assert_equal normalize_nquads(File.read(EXPECTED_NQ)), normalize_nquads(actual_graph.dump(:nquads))
  end

  test "fixture pack export includes a complete event with linked place and offer semantics" do
    graph = jsonld_to_graph(ExportArtsdataService.call(seedurl: FIXTURE_SEEDURL))
    event = RDF::URI("http://kg.footlight.io/resource/distillator-full-event")

    assert graph.query([event, RDF.type, RDF::Vocab::SCHEMA.Event]).to_a.any?, "expected schema:Event triple"
    assert graph.query([event, RDF::Vocab::SCHEMA.location, nil]).to_a.any?, "expected linked schema:location"
    assert graph.query([event, RDF::Vocab::SCHEMA.offers, nil]).to_a.any?, "expected schema:offers"
    assert graph.query([event, RDF::Vocab::SCHEMA.eventStatus, RDF::URI("http://schema.org/EventScheduled")]).to_a.any?, "expected reconciled eventStatus URI"
    assert graph.query([event, RDF::Vocab::SCHEMA.eventAttendanceMode, RDF::URI("http://schema.org/OnlineEventAttendanceMode")]).to_a.any?, "expected reconciled attendance mode URI"
  end

  private

  def jsonld_to_graph(jsonld)
    RDF::Graph.new << JSON::LD::API.toRdf(JSON.parse(jsonld))
  end

  def normalize_nquads(nquads)
    nquads.to_s.lines.map(&:strip).reject(&:blank?).sort.join("\n")
  end

  def diff_message(diff)
    [
      "added_count=#{diff.added_count} removed_count=#{diff.removed_count} same_count=#{diff.same_count}",
      ("added:\n" + diff.added.first(10).join("\n") if diff.added.any?),
      ("removed:\n" + diff.removed.first(10).join("\n") if diff.removed.any?),
      ("changed_literal_values:\n" + diff.changed_literal_values.first(10).map(&:inspect).join("\n") if diff.changed_literal_values.any?),
      ("changed_uri_objects:\n" + diff.changed_uri_objects.first(10).map(&:inspect).join("\n") if diff.changed_uri_objects.any?)
    ].compact.join("\n\n")
  end
end
