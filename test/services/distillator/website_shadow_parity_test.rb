require "test_helper"

class Distillator::WebsiteShadowParityTest < ActiveSupport::TestCase
  BASE_JSONLD = '{"@context":{"schema":"http://schema.org/"},"@id":"http://example.org/event","schema:name":"One"}'.freeze
  CHANGED_JSONLD = '{"@context":{"schema":"http://schema.org/"},"@id":"http://example.org/event","schema:name":"Different"}'.freeze

  test "identical statement and graph snapshots pass regardless of row ordering" do
    before = snapshot
    after = snapshot
    after["statements"] = before["statements"].reverse
    assert Distillator::WebsiteShadowParity.call(baseline: before, shadow: after).passed?
  end

  test "changed statement cache fails even if exported graph stays identical" do
    after = snapshot
    after["statements"] = after["statements"].map(&:dup)
    after["statements"][0][4] = "Changed title"
    result = Distillator::WebsiteShadowParity.call(baseline: snapshot, shadow: after)
    assert_equal "failed", result.status
    assert_includes result.differences.keys, "statements"
    assert_equal 0, result.graph_diff.added_count
  end

  test "changed stable rdf URI fails independently from statement comparison" do
    after = snapshot
    after["webpages"] = after["webpages"].map(&:dup)
    after["webpages"][0][1] = "footlight:changed-id"
    result = Distillator::WebsiteShadowParity.call(baseline: snapshot, shadow: after)
    assert_equal "failed", result.status
    assert_includes result.differences.keys, "webpages"
  end

  test "changed export graph fails even when all statements are identical" do
    after = snapshot
    after["export_jsonld"] = CHANGED_JSONLD
    result = Distillator::WebsiteShadowParity.call(baseline: snapshot, shadow: after)
    assert_equal "failed", result.status
    assert_includes result.differences.keys, "artsdata_graph"
    assert_operator result.graph_diff.added_count, :>, 0
    assert_operator result.graph_diff.removed_count, :>, 0
  end

  test "non-ResourceList source changes fail strict parity" do
    after = snapshot
    after["event_sources"] = [{"id" => 12, "algorithm_value" => "xpath=//h2"}]
    assert_includes Distillator::WebsiteShadowParity.call(baseline: snapshot, shadow: after).differences.keys, "event_sources"
  end

  private

  def snapshot
    {
      "schema_version" => 1,
      "website" => {"seedurl" => "dansedanse-ca", "graph_name" => "https://example.org"},
      "event_sources" => [{"id" => 12, "algorithm_value" => "xpath=//h1"}],
      "webpages" => [["https://example.org/fr/a", "footlight:a", "fr", "Event", nil]],
      "statements" => [
        ["https://example.org/fr/a", "footlight:a", 12, "fr", "Title A", "ok", false, true],
        ["https://example.org/fr/b", "footlight:b", 13, "fr", "Title B", "ok", false, true]
      ],
      "export_jsonld" => BASE_JSONLD
    }
  end
end
