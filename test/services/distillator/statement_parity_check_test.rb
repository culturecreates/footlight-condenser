require "test_helper"

class Distillator::StatementParityCheckTest < ActiveSupport::TestCase
  setup do
    @website = Website.create!(name: "Paired tests", seedurl: "paired-tests", graph_name: "https://example.org/parity", default_language: "en", distillator_mode: "shadow")
    @page = @website.webpages.create!(url: "https://example.org/event", rdf_uri: "rdf:paired", language: "en", rdfs_class: rdfs_classes(:one))
    @sources = {}
    { "Title" => "//title/text()", "Dates" => "//time/text()", "Location" => "//div[@id='location']/text()", "Price" => "//span[@id='price']/text()" }.each do |label, xpath|
      property = Property.create!(label: label, value_datatype: "MyString", uri: "https://example.org/#{label}", rdfs_class: rdfs_classes(:one))
      @sources[label] = @website.sources.create!(property: property, language: "en", selected: true, render_js: false, algorithm_value: "xpath=#{xpath}")
    end
    @helper = StatementsHelper.build_refresh_proxy(cookies: {})
  end

  test "matching extracted values pass without updating stored statements" do
    stat = Statement.create!(webpage: @page, source: @sources["Title"], cache: "Stored title", status: "ok", selected_individual: true)
    before = stat.reload.attributes
    fingerprint = Distillator::TransitionFingerprint.call(@website)
    result = compare(html, html)
    assert_equal :checked, result.status
    assert_equal 4, result.artifacts.length
    assert_equal before, stat.reload.attributes
    assert_equal fingerprint, Distillator::TransitionFingerprint.call(@website)
  end

  test "a changed critical value fails even when both sides parse" do
    result = compare(html, html(date: "2027-02-02"))
    assert_equal :failed, result.status
    assert_equal ["Dates"], result.critical_failures.map { |row| row[:property_label] }
    assert_equal "2027-01-01", result.critical_failures.first[:legacy]
    assert_equal "2027-02-02", result.critical_failures.first[:condenser]
  end

  test "optional value changes require review" do
    result = compare(html, html(price: "30"))
    assert_equal :warning, result.status
    assert_empty result.critical_failures
    assert_equal ["Price"], result.optional_failures.map { |row| row[:property_label] }
  end

  test "missing snapshots are inconclusive" do
    assert_equal :pending, compare(nil, html).status
  end

  test "missing required source coverage cannot pass" do
    @sources["Dates"].destroy!
    assert_equal :pending, compare(html, html).status
  end

  test "matching blank required values do not establish validity" do
    assert_equal :failed, compare(html(title: ""), html(title: "")).status
  end

  test "nested DSL fetches without recorded resources are inconclusive" do
    @sources["Title"].update!(algorithm_value: %q{url='https://example.org/other';xpath=//title/text()})
    result = compare(html, html)
    assert_equal :pending, result.status, result.artifacts.inspect
    assert_equal "MigrationComparatorFetchUnsupported", result.artifacts.first[:legacy_error]["error_type"]
  end

  test "different locations block even though export serialization could still agree" do
    result = compare(html, html.sub("Hall", "Other hall"))
    assert_equal :failed, result.status
    assert_equal ["Location"], result.critical_failures.map { |row| row[:property_label] }
  end

  test "ticket link differences are retained for optional review" do
    property = Property.create!(label: "Ticket URL", value_datatype: "MyString", uri: "https://example.org/ticket", rdfs_class: rdfs_classes(:one))
    @website.sources.create!(property: property, selected: true, language: "en", render_js: false, algorithm_value: "xpath=//a/@href")
    result = compare(html + '<a href="https://tickets.example/old">Tickets</a>', html + '<a href="https://tickets.example/new">Tickets</a>')
    assert_equal :warning, result.status
    assert_equal "https://tickets.example/old", result.optional_failures.first[:legacy]
    assert_equal "https://tickets.example/new", result.optional_failures.first[:condenser]
  end

  test "French and rendered source values use the supplied snapshots" do
    @page.update!(language: "fr")
    @sources.each_value { |source| source.update!(language: "fr", render_js: true) }
    result = compare(html(title: "Événement"), html(title: "Événement modifié"))
    assert_equal :failed, result.status
    assert_equal "fr", result.critical_failures.first[:language]
    assert_equal "Événement", result.critical_failures.first[:legacy]
  end

  test "ordered date values are not silently sorted into equality" do
    @sources["Dates"].update!(algorithm_value: "xpath=//time/text();ruby=$array")
    left = html.sub("</time>", "</time><time>2027-02-02</time>")
    right = left.sub("2027-01-01", "TEMP").sub("2027-02-02", "2027-01-01").sub("TEMP", "2027-02-02")
    assert_equal :failed, compare(left, right).status
  end

  test "mixed rendered and plain sources cannot be certified from one snapshot pair" do
    @sources["Title"].update!(render_js: true)
    result = compare(html, html)
    assert_equal :pending, result.status
    assert_equal "mixed_fetch_profiles", result.url_results.first[:reason]
  end

  test "strict comparison blocks price differences while standard comparison records a warning" do
    assert_equal :warning, compare(html, html(price: "30")).status
    result = compare(html, html(price: "30"), strict: true)
    assert_equal :failed, result.status
    assert_equal "strict_statement_parity_failed", result.reason
    assert_equal ["Price"], result.critical_failures.map { |row| row[:property_label] }
    assert_equal false, result.critical_failures.first[:core_field]
    assert_equal "blocker", result.critical_failures.first[:severity]
  end

  test "strict agreement does not make optional fields mandatory or accept unsupported inputs" do
    assert_equal :checked, compare(html(price: ""), html(price: ""), strict: true).status
    assert_equal :failed, compare(html(title: ""), html(title: ""), strict: true).status
    assert_equal :pending, compare(nil, html, strict: true).status
    @sources["Price"].update!(algorithm_value: %q{url='https://example.org/price';xpath=//title/text()})
    assert_equal :pending, compare(html, html, strict: true).status
  end

  private

  def html(title: "Shared", date: "2027-01-01", price: "20")
    "<html><head><title>#{title}</title></head><body><time>#{date}</time><div id='location'>Hall</div><span id='price'>#{price}</span></body></html>"
  end

  def compare(legacy, candidate, strict: false)
    Distillator::StatementParityCheck.call(website: @website, webpages: [@page], refresh_helper: @helper,
      url_results: [{ url: @page.url, fetch_status: "passed", legacy_html: legacy, condenser_html: candidate }], strict: strict)
  end
end
