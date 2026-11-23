require "test_helper"
require "tempfile"

class Distillator::ComparisonRefreshProxyTest < ActiveSupport::TestCase
  setup do
    @helper = Distillator::ComparisonRefreshProxy.new(cookies: {})
    @helper.define_singleton_method(:artsdata_recon_url) { "https://recon.example/recon" }
    @url = "https://recon.example/recon?query=Venue&type=Place"
  end

  test "identical requests including empty results are reused only within one helper instance" do
    HTTParty.expects(:get).with(@url, timeout: 10).twice.returns({ "result" => [] })
    3.times { assert_equal({ "result" => [] }, @helper.reconciliation_response_for(@url)) }
    another = Distillator::ComparisonRefreshProxy.new(cookies: {})
    another.reconciliation_response_for(@url)
    assert_equal 1, @helper.reconciliation_performance["http_requests"]
    assert_equal 2, @helper.reconciliation_performance["cache_hits"]
    assert_equal 0, another.reconciliation_performance["cache_hits"]
  end

  test "responses are copied so one consumer cannot change another comparison" do
    HTTParty.expects(:get).once.returns({ "result" => [{ "name" => "Good venue", "id" => "K1" }] })
    first = @helper.reconciliation_response_for(@url)
    first["result"].first["name"] = "Changed locally"
    assert_equal "Good venue", @helper.reconciliation_response_for(@url)["result"].first["name"]
  end

  test "file-backed comparison reuses immutable snapshots even after a different lookup" do
    venue = { "result" => [{ "name" => "Original venue", "id" => "K1" }] }
    HTTParty.expects(:get).with(@url, timeout: 10).once.returns(venue)
    another_url = "#{@url}&lang=fr"
    HTTParty.expects(:get).with(another_url, timeout: 10).once.returns({ "result" => [] })

    Tempfile.create("reconciliation-test", anonymous: true, binmode: true) do |file|
      helper = Distillator::ComparisonRefreshProxy.new(response_file: file, cookies: {})
      helper.reconciliation_response_for(@url)["result"].first["name"] = "Changed locally"
      assert_equal({ "result" => [] }, helper.reconciliation_response_for(another_url))
      assert_equal "Original venue", helper.reconciliation_response_for(@url).dig("result", 0, "name")
      assert_equal 1, helper.reconciliation_performance["cache_hits"]
      assert_operator file.size, :>, 0
    end
  end

  test "region-specific request URLs cannot share a cached result" do
    places = %w[QC ON].map { |region| Struct.new(:website).new(Struct.new(:province).new(region)) }
    regions = []
    HTTParty.expects(:get).with do |url, options|
      query = URI.decode_www_form(URI.parse(url).query).to_h
      regions << JSON.parse(query.fetch("queries")).dig("q0", "properties", 0, "v")
      options == { timeout: 10 }
    end.twice.returns({ "q0" => { "result" => [] } })
    places.each { |page| 2.times { @helper.fetch_cckg_hits("Venue", "Place", page, true) } }
    assert_equal %w[QC ON], regions
    assert_equal 2, @helper.reconciliation_performance["cache_hits"]
  end

  test "cached raw hits still apply each webpage's self-link exclusion" do
    @helper.stubs(:search_condenser).returns({ data: [] })
    HTTParty.expects(:get).once.returns({ "result" => [
      { "name" => "Venue", "id" => "K1" }, { "name" => "Venue", "id" => "K2" }
    ] })
    website = Struct.new(:province).new(nil)
    page_type = Struct.new(:website, :rdf_uri)
    property = Struct.new(:expected_class).new("Place")
    first = @helper.search_for_uri("Venue", property, page_type.new(website, "http://kg.artsdata.ca/resource/K1"))
    second = @helper.search_for_uri("Venue", property, page_type.new(website, "http://kg.artsdata.ca/resource/K2"))
    assert_equal [["Venue", "http://kg.artsdata.ca/resource/K2"]], first.drop(2)
    assert_equal [["Venue", "http://kg.artsdata.ca/resource/K1"]], second.drop(2)
  end

  test "timeouts and invalid responses are not cached" do
    HTTParty.expects(:get).with(@url, timeout: 10).times(3).raises(Net::ReadTimeout).then.returns({ "error" => "Unavailable" }).then.returns({ "result" => [] })
    assert_raises(Net::ReadTimeout) { @helper.reconciliation_response_for(@url) }
    assert_raises(RuntimeError) { @helper.reconciliation_response_for(@url) }
    assert_equal({ "result" => [] }, @helper.reconciliation_response_for(@url))
    assert_equal 3, @helper.reconciliation_performance["http_requests"]
    assert_equal 2, @helper.reconciliation_performance["errors"]
    assert_equal 0, @helper.reconciliation_performance["cache_hits"]
  end

  test "non-success HTTP or malformed result shapes cannot be cached as empty matches" do
    bad = Struct.new(:code, :parsed_response).new(503, { "result" => [] })
    HTTParty.expects(:get).with(@url, timeout: 10).times(3).returns(bad).then.returns({}).then.returns({ "result" => [] })
    2.times { assert_raises(RuntimeError) { @helper.reconciliation_response_for(@url) } }
    assert_equal({ "result" => [] }, @helper.reconciliation_response_for(@url))
    counters = @helper.reconciliation_performance
    assert_equal({ "503" => 1 }, counters["http_error_statuses"])
    assert_equal 2, counters["retried_lookups"]
    assert_equal 2, counters.dig("by_type", "Place", "errors")
  end

  test "paired extraction reuses venue and organization lookups across pages without changing values or stored statements" do
    site = Website.create!(name: "Cached comparison", seedurl: "cached-comparison", graph_name: "https://example.org/cache", default_language: "en")
    sources = [["Location probe", "Place", "venue"], ["Organizer probe", "Organization", "organizer"]].map do |label, expected, id|
      property = Property.create!(label: label, expected_class: expected, value_datatype: "xsd:anyURI",
        uri: "https://example.org/#{id}", rdfs_class: rdfs_classes(:one))
      site.sources.create!(property: property, language: "en", selected: true, render_js: false, algorithm_value: "xpath=//span[@id='#{id}']/text()")
    end
    HTTParty.expects(:get).with { |url, options| url.start_with?("https://recon.example/") && options == { timeout: 10 } }.times(3).returns({ "result" => [] })
    html = "<span id='venue'>Same venue</span><span id='organizer'>Same organizer</span>"
    100.times do |index|
      page = site.webpages.create!(url: "https://example.org/#{index}", rdf_uri: "rdf:#{index}", language: "en", rdfs_class: rdfs_classes(:one))
      comparison = nil
      assert_no_difference ["Statement.count", "Distillator::RolloutEvent.count"] do
        comparison = Distillator::MigrationComparator.new(website: site, webpage: page, sources: sources,
          legacy_html: html, condenser_html: html, refresh_helper: @helper).compare_statements
      end
      assert_equal Distillator::MigrationComparator::MATCH, comparison.verdict
      assert_equal ["Same venue", "Place"], comparison.artifacts.first[:legacy]
      assert comparison.artifacts.first.dig(:timing, :legacy, :formatting_ms) >= 0
    end
    assert_equal 3, @helper.reconciliation_performance["http_requests"]
    assert_equal 797, @helper.reconciliation_performance["cache_hits"]
  end

  test "identical failures are reused within a source pair and a subsequent pair can recover" do
    site = websites(:one)
    page = site.webpages.first
    property = Property.create!(label: "Lookup probe", value_datatype: "xsd:anyURI", expected_class: "Place",
      uri: "https://example.org/lookup", rdfs_class: page.rdfs_class)
    source = site.sources.create!(property: property, selected: true, language: "en", algorithm_value: "xpath=//span/text()")
    HTTParty.expects(:get).with { |url, options| url.end_with?("&type=Place") && options == { timeout: 10 } }
      .twice.raises(Net::ReadTimeout).then.returns({ "result" => [] })
    compare = -> do
      Distillator::MigrationComparator.new(website: site, webpage: page, sources: [source],
        legacy_html: "<span>Unknown venue</span>", condenser_html: "<span>Unknown venue</span>", refresh_helper: @helper).compare_statements
    end
    comparison = compare.call
    assert_equal Distillator::MigrationComparator::SHARED_EXTRACTION_ERROR, comparison.verdict
    assert_equal "LinkedDataLookupError", comparison.artifacts.first[:legacy_error]["error_type"]
    assert_equal "LinkedDataLookupError", comparison.artifacts.first[:condenser_error]["error_type"]
    assert_equal Distillator::MigrationComparator::MATCH, compare.call.verdict
    stats = @helper.reconciliation_performance
    assert_equal [4, 2, 1, 1, 1], stats.values_at("lookups", "http_requests", "cache_hits", "failure_reuses", "retried_lookups")
    assert_equal({ "Net::ReadTimeout" => 1 }, stats["error_classes"])
    assert_equal 1, stats.dig("by_source", source.id.to_s, "failure_reuses")
  end

  test "a failed Person fallback cannot pass a paired Organization comparison" do
    site = websites(:one)
    page = site.webpages.first
    property = Property.create!(label: "Organization probe", value_datatype: "xsd:anyURI", expected_class: "Organization",
      uri: "https://example.org/organization-lookup", rdfs_class: page.rdfs_class)
    source = site.sources.create!(property: property, selected: true, language: "en", algorithm_value: "xpath=//span/text()")
    @helper.stubs(:search_condenser).returns({ data: [] })
    HTTParty.expects(:get).with { |url, _| url.end_with?("&type=Organization") }.once.returns(
      { "result" => [{ "name" => "Example Ensemble", "id" => "K1", "match" => true }] })
    HTTParty.expects(:get).with { |url, _| url.end_with?("&type=Person") }.once.raises(Net::ReadTimeout)

    comparison = Distillator::MigrationComparator.new(website: site, webpage: page, sources: [source],
      legacy_html: "<span>Example Ensemble</span>", condenser_html: "<span>Example Ensemble</span>", refresh_helper: @helper).compare_statements

    assert_equal Distillator::MigrationComparator::SHARED_EXTRACTION_ERROR, comparison.verdict
    artifact = comparison.artifacts.sole
    assert_equal ["comparison_reconciliation", "comparison_reconciliation"], artifact.values_at(:legacy_error, :condenser_error).pluck("source")
    assert_equal 1, @helper.reconciliation_performance.dig("by_type", "Person", "http_requests")
    assert_equal 3, @helper.reconciliation_performance.dig("by_type", "Person", "failure_reuses")
  end
end
