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

  test "fixture pack export matches the current production equivalent export path after normalization" do
    actual = Distillator::ExportNormalizer.normalize(ExportArtsdataService.call(seedurl: FIXTURE_SEEDURL))
    expected = Distillator::ExportNormalizer.normalize(ExportArtsdataService.production_equivalent(seedurl: FIXTURE_SEEDURL))

    assert_equal expected, actual
  end

  test "fixture pack export includes a complete event with linked place and offer semantics" do
    graph = jsonld_to_graph(ExportArtsdataService.call(seedurl: FIXTURE_SEEDURL))
    event = RDF::URI("http://kg.footlight.io/resource/distillator-full-event")

    assert graph.query([event, RDF.type, RDF::Vocab::SCHEMA.Event]).to_a.any?, "expected schema:Event triple"
    assert graph.query([event, RDF::Vocab::SCHEMA.location, nil]).to_a.any?, "expected linked schema:location"
    place = RDF::URI("http://kg.footlight.io/resource/distillator-main-hall")
    assert graph.has_statement?(RDF::Statement.new(place, RDF.type, RDF::Vocab::SCHEMA.Place))
    assert graph.has_statement?(RDF::Statement.new(place, RDF::Vocab::SCHEMA.name, "Main Hall"))
    assert graph.query([event, RDF::Vocab::SCHEMA.offers, nil]).to_a.any?, "expected schema:offers"
    assert graph.query([event, RDF::Vocab::SCHEMA.eventStatus, RDF::URI("http://schema.org/EventScheduled")]).to_a.any?, "expected reconciled eventStatus URI"
    assert graph.query([event, RDF::Vocab::SCHEMA.eventAttendanceMode, RDF::URI("http://schema.org/OnlineEventAttendanceMode")]).to_a.any?, "expected reconciled attendance mode URI"
  end

  test "diagnostic fetch-cache title never contaminates Artsdata fixture export" do
    page = webpages(:distillator_full_event)
    original_html = "<html><title>Distillator Full Event</title><body><h1>Distillator Full Event</h1></body></html>"
    baseline = Distillator::ExportNormalizer.normalize(ExportArtsdataService.call(seedurl: FIXTURE_SEEDURL))
    assert_includes baseline, "Distillator Full Event"

    Distillator::FetchCache.delete_all
    key = Distillator::WringerUrlKey.call(page.url)
    cache = Distillator::FetchCache.create!(
      uri_key: key.uri_key, normalized_url: key.normalized_url,
      name: "Distillator Full Event", html: original_html, body: original_html,
      scrape_date: 2.days.ago, successful_refresh: 1.day.ago,
      http_response_code: 200,
      signals: { "body_profile" => { "backend" => "legacy", "request_method" => "GET", "render_js" => false, "absolute_src" => false } }
    )

    Distillator::FetchService.expects(:fetch_result).once.returns(
      status: :abort,
      body: ["abort_update", { error_type: "http_server_error" }],
      raw_body: "<html><title>Server Error</title></html>",
      headers: { content_type: "text/html" },
      final_url: page.url, redirect_chain: [],
      wringer: { signals: { network_status: "ok", content_type: "html" }, hints: [] },
      http_code: 500, duration_ms: 2.0, fetch_path: "legacy"
    )
    result = Distillator::FetchCacheStore.fetch(uri: page.url, mode: :legacy, force_scrape: true)

    assert_equal "Distillator Full Event --!^!-- Server Error", cache.reload.name
    assert_equal original_html, cache.body
    assert_equal false, result.content_success?

    exported = Distillator::ExportNormalizer.normalize(ExportArtsdataService.call(seedurl: FIXTURE_SEEDURL))
    assert_equal baseline, exported
    refute_includes exported, "--!^!--"
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
