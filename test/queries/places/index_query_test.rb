require "test_helper"

class Places::IndexQueryTest < ActiveSupport::TestCase
  def build_results_for(raw_places)
    query = Places::IndexQuery.new(
      filters: { seedurl: websites(:one).seedurl },
      sort: "rdf_uri",
      direction: "asc",
      page: 1,
      per_page: 50
    )
    query.stubs(:raw_places).returns(raw_places)
    query.call
  end

  test "returns place rows for a seedurl" do
    results = Places::IndexQuery.call(
      filters: { seedurl: websites(:one).seedurl },
      sort: "rdf_uri",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert results.is_a?(Enumerable)
  end

  test "falls back on invalid sort and direction" do
    results = Places::IndexQuery.call(
      filters: { seedurl: websites(:one).seedurl },
      sort: "bogus",
      direction: "sideways",
      page: 1,
      per_page: 50
    )

    uris = results.map { |row| row[:rdf_uri] }
    assert_equal uris.sort, uris
  end

  test "returns place row for cache containing simple linked place array" do
    results = build_results_for([
      ["uri:simple", '["Wednesday @ Salle Andre-Mathieu", "Place", ["Salle Andre-Mathieu", "adr:salle-andre-mathieu"]]', "en", "http://example.com/simple"]
    ])

    row = results.first
    assert_equal "uri:simple", row[:rdf_uri]
    assert_equal "Wednesday @ Salle Andre-Mathieu", row[:linked_name]
    assert_equal "adr:salle-andre-mathieu", row[:linked_uri]
  end

  test "returns place row for cache containing nested linked place arrays" do
    results = build_results_for([
      ["uri:nested", '[["Saturday @ Theatre des Muses", "Place", ["Theatre des Muses", "http://example.com/muses"]], ["Monday @ Theatre des Muses", "Place", ["Theatre des Muses", "http://example.com/muses"]]]', "en", "http://example.com/nested"]
    ])

    assert_equal 2, results.length
    assert_equal ["Monday @ Theatre des Muses", "Saturday @ Theatre des Muses"], results.map { |row| row[:linked_name] }.sort
  end

  test "returns place row for cache containing JSON string payload" do
    results = build_results_for([
      ["uri:json-string", '"Main Hall"', "en", "http://example.com/json-string"]
    ])

    row = results.first
    assert_equal "Main Hall", row[:linked_name]
    assert_equal "", row[:linked_uri]
    assert_equal "Place", row[:place_class]
  end

  test "returns place row for cache containing raw string fallback" do
    results = build_results_for([
      ["uri:raw-string", "Fallback Hall", "en", "http://example.com/raw-string"]
    ])

    row = results.first
    assert_equal "Fallback Hall", row[:linked_name]
    assert_equal "", row[:linked_uri]
  end

  test "returns place row for cache containing array fallback" do
    results = build_results_for([
      ["uri:array-fallback", ["Array Hall", "Place", ["Main Hall", "adr:array-hall"]], "en", "http://example.com/array-fallback"]
    ])

    row = results.first
    assert_equal "Array Hall", row[:linked_name]
    assert_equal "adr:array-hall", row[:linked_uri]
    assert_equal "Place", row[:place_class]
  end
end
