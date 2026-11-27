require "test_helper"

class Distillator::WebsiteShadowParityTest < ActiveSupport::TestCase
  # Pure snapshot comparison: unrelated fixtures are unnecessary.
  self.fixture_table_names = []

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

  test "Danse Danse test copy normalizes expected website/source/RDF IDs" do
    original = snapshot
    original["event_sources"] = [{"id" => 12, "website_id" => 10, "property_id" => 20,
      "algorithm_value" => "xpath=//h1", "language" => "fr"}]
    original["webpages"] = [["https://example.org/fr/a", "http://kg.footlight.io/resource/dansedanse-ca_a",
      "fr", "Event", nil]]
    original["statements"] = [["https://example.org/fr/a",
      "http://kg.footlight.io/resource/dansedanse-ca_a", 12, "fr", "Title A", "ok", false, true]]
    original["export_jsonld"] = %q({"@id":"http://kg.footlight.io/resource/dansedanse-ca_a","http://schema.org/name":"Title A"})

    copy = Marshal.load(Marshal.dump(original))
    copy["test_copy_origin_seedurl"] = "dansedanse-ca"
    copy["website"]["seedurl"] = "dansedansetest-ca"
    copy["website"]["name"] = "Danse Danse QA"
    copy["event_sources"][0]["id"] = 912
    copy["event_sources"][0]["website_id"] = 21
    test_uri = Websites::CreateTestCopy.test_uri("http://kg.footlight.io/resource/dansedanse-ca_a",
      seedurl: "dansedansetest-ca")
    copy["webpages"][0][1] = test_uri
    copy["statements"][0][1] = test_uri
    copy["statements"][0][2] = 912
    copy["export_jsonld"] = %Q({"@id":"#{test_uri}","http://schema.org/name":"Title A"})
    result = Distillator::WebsiteShadowParity.call(baseline: original, shadow: copy)
    assert result.passed?, result.differences.inspect

    copy["statements"][0][4] = "Modified title"
    result = Distillator::WebsiteShadowParity.call(baseline: original, shadow: copy)
    assert_equal "failed", result.status
    assert_includes result.differences.keys, "statements"
  end

  test "clone graph normalizes derived event fragments without normalizing unrelated URI objects" do
    original = snapshot
    event_uri = "http://kg.footlight.io/resource/dansedanse-ca_a"
    original["webpages"] = [["https://example.org/fr/a", event_uri, "fr", "Event", nil]]
    original["statements"] = []
    original["event_sources"] = []
    original["export_jsonld"] = {
      "@id" => event_uri,
      "http://schema.org/offers" => { "@id" => "#{event_uri}#Offer",
        "http://schema.org/price" => "30" },
      "http://schema.org/location" => { "@id" => "http://kg.artsdata.ca/resource/K1" }
    }.to_json

    copy = Marshal.load(Marshal.dump(original))
    copy["website"]["seedurl"] = "dansedansetest-ca"
    copy["website"]["name"] = "Danse Danse QA"
    copy["test_copy_origin_seedurl"] = "dansedanse-ca"
    copied_uri = Websites::CreateTestCopy.test_uri(event_uri, seedurl: "dansedansetest-ca")
    copy["webpages"][0][1] = copied_uri
    copy["export_jsonld"] = original["export_jsonld"].gsub(event_uri, copied_uri)
    assert Distillator::WebsiteShadowParity.call(baseline: original, shadow: copy).passed?

    # An actual change to an unrelated linked location is not normalized away.
    copy["export_jsonld"] = copy["export_jsonld"].sub("/K1", "/K2")
    result = Distillator::WebsiteShadowParity.call(baseline: original, shadow: copy)
    assert_equal "failed", result.status
    assert_includes result.differences.keys, "artsdata_graph"
  end

  test "QA comparison requires original website name rather than silently accepting an incomplete baseline" do
    original = snapshot
    original["website"].delete("name")
    copy = Marshal.load(Marshal.dump(original))
    copy["test_copy_origin_seedurl"] = "dansedanse-ca"
    copy["website"]["seedurl"] = "dansedansetest-ca"
    assert_raises(KeyError) { Distillator::WebsiteShadowParity.call(baseline: original, shadow: copy) }
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
      "website" => {"name" => "Danse Danse", "seedurl" => "dansedanse-ca",
        "graph_name" => "https://example.org", "default_language" => "fr"},
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
