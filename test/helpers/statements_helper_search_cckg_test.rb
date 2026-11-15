require 'test_helper'

# StatementsHelper tests for search_cckg() only
class StatementsHelperSearchCckgTest < ActionView::TestCase
  tests StatementsHelper
  include DslRunnerTestHelper

  test "Partytime's single extracted venue does not expand into city-suffix matches and exports six performances" do
    # Names and identities are from the recorded replay; no scores or automatic
    # match flags were supplied, so this fixture asserts neither.
    hits = JSON.parse(Rails.root.join("test/fixtures/files/reconciliation/partytime_location_candidates.json").read)
    query = "Le Memphis Cabaret, Trois-Rivières, QC"
    webpage = webpages(:four)
    self.stubs(:search_condenser).returns(data: [])
    self.expects(:fetch_cckg_hits).with(query, "Place", webpage, false).returns(hits)
    expect_no_fetch_seams

    algorithm = <<~DSL
      xpath=//div[@itemprop='location']//span[@itemprop='name'] | //li[@itemprop="location"] | //li[contains(@class, 'performances-sub-item')]//a/span[2]/text()
      ;ruby=$array.map{|e|
        parts = e.split('@')
        location = parts.length > 1 ? parts[1] : parts[0]
        location.squish
      }.uniq
    DSL
    runner, = build_runner_with_html(html: "<div itemprop='location'><span itemprop='name'>#{query}</span></div>")
    raw = runner.run(algorithm)
    assert_equal [query], raw
    formatted = format_datatype(raw, properties(:seven), webpage)
    assert_equal [query, "Place", ["Le Memphis Cabaret", "http://kg.artsdata.ca/resource/K5-706"]], formatted

    uri = "http://kg.footlight.io/resource/culturemauricie_lepointdevente-com_partytime2026"
    base = { subject: uri, webpage_class_name: "Event", rdfs_class_name: "Event", language: "" }
    dates = %w[2026-11-20 2026-11-21 2026-12-04 2026-12-05 2026-12-11 2026-12-12].map { |day| "#{day}T20:30:00-05:00" }
    graph = JsonldGenerator.build_graph([
      base.merge(predicate: "http://schema.org/startDate", datatype: "xsd:dateTime", value: dates.to_json),
      base.merge(predicate: "http://schema.org/location", datatype: "xsd:anyURI", value: formatted.to_json),
      base.merge(predicate: "http://schema.org/name", datatype: "xsd:string", value: "Partytime 2026")
    ], for_artsdata: true)
    graph = JsonldGenerator.make_event_series(graph, uri)
    children = graph.query([RDF::URI(uri), RDF::URI("http://schema.org/subEvent"), nil]).map(&:object)
    assert_equal 6, children.uniq.count
    children.each do |child|
      assert_equal [RDF::URI("http://kg.artsdata.ca/resource/K5-706")],
        graph.query([child, RDF::URI("http://schema.org/location"), nil]).map(&:object)
    end
  end

  test "Wilfrid-Pelletier text cannot match Theatre Denise-Pelletier through its hyphen suffix" do
    query = "Yoann Bourgeois & Patrick Watson, Salle Wilfrid-Pelletier"
    self.expects(:fetch_cckg_hits).with(query, "Organization", nil, false).returns([
      { "id" => "K10-418", "name" => "Théâtre Denise-Pelletier" }
    ])
    self.expects(:fetch_cckg_hits).with(query, "Person", nil, false).returns([
      { "id" => "K12-450", "name" => "Patrick Watson" }
    ])
    assert_equal({ data: [] }, search_cckg(query, "Organization"))
    assert_equal({ data: [["Patrick Watson", "http://kg.artsdata.ca/resource/K12-450"]] }, search_cckg(query, "Person"))
  end

  test "full names with internal hyphens remain matchable in descriptive text" do
    query = "Spectacle à La P'tite Grenouille Trois-Rivières, QC"
    self.expects(:fetch_cckg_hits).with(query, "Place", nil, false).returns([
      { "id" => "K5-1456", "name" => "La P'tite Grenouille Trois-Rivières" }
    ])
    assert_equal({ data: [["La P'tite Grenouille Trois-Rivières", "http://kg.artsdata.ca/resource/K5-1456"]] }, search_cckg(query, "Place"))
  end

  test "search_cckg: should search cckg for uris that match 100%" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: should search cckg for uris that match 100%') do
      expected = {:data=>[["Place des Arts - Théâtre Maisonneuve", "http://kg.artsdata.ca/resource/K11-11"]]}
      actual = search_cckg "Théâtre Maisonneuve", "Place"
      assert_equal expected, actual
    end
  end

  test "search_cckg: should search cckg for uris by matching name in substring" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: should search cckg for uris by matching name in substring') do
      expected = {:data=>[["St. Lawrence Centre for the Arts - Bluma Appel Theatre", "http://kg.artsdata.ca/resource/K11-6"], ["Canadian Stage - Berkeley Street Theatre", "http://kg.artsdata.ca/resource/K11-14"]]}
      actual = search_cckg "The locations is in the lovely Bluma Appel Theatre and Berkeley Street Theatre.", "Place"
      assert_equal expected, actual
    end
  end

  test "search_cckg: should search cckg for VaughnCo Entertainment presents" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: should search cckg for VaughnCo Entertainment presents') do
      expected = {data:[["VaughnCo Entertainment", "http://kg.artsdata.ca/resource/K10-148"]]}
      actual = search_cckg "VaughnCo Entertainment presents", "Organization"
      assert_equal expected, actual
    end
  end
  

  test "search_cckg: should search cckg for Wajdi Mouawad" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: should search cckg for Wajdi Mouawad') do
      expected = {data:[["Wajdi Mouawad", "http://kg.artsdata.ca/resource/K12-362"]]}
      actual = search_cckg "Wajdi Mouawad", "Person"
      assert_equal expected, actual
    end
  end
  

  test "search_cckg: should search cckg for nowhere" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: should search cckg for nowhere') do
      expected = {:data=>[]}
      actual = search_cckg "Show is at nowhere", "Place"
      assert_equal expected, actual
    end
  end

  test "search_cckg: remove duplicates" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: remove duplicates') do
      expected = {data:[["Canadian Stage - Berkeley Street Theatre", "http://kg.artsdata.ca/resource/K11-14"]]}
      actual = search_cckg "The locations is in the lovely Berkeley Street Theatre and Canadian Stage - Berkeley Street Theatre.", "Place"
      assert_equal expected, actual
    end
  end
  
  # Common words: example Person name that is removed "wiL", "http://kg.artsdata.ca/resource/K12-32"
  test "search_cckg: should not match names with common words" do  
    VCR.use_cassette('StatementsHelperSearchCckgTest: should not match names with common words') do
      expected = {data:[]}
      actual = search_cckg "The word will contains part of a first name.", "Person"
      assert_equal expected, actual
    end
  end

  test "search_cckg: should match names with single neutral quote" do  
    VCR.use_cassette('StatementsHelperSearchCckgTest: should match names with single neutral quote') do
      expected = {:data=>[["La P'tite Église (Shippagan)", "http://kg.artsdata.ca/resource/K11-131"]]}
      actual = search_cckg "Shippagan 20 h 00 La P'tite Église (Shippagan)", "Place"
      assert_equal expected, actual
    end
  end

  test "search_cckg: should match names with single curved quote" do  
    VCR.use_cassette('StatementsHelperSearchCckgTest: should match names with single curved quote') do
      expected = {:data=>[["Emily D’Angelo", "http://kg.artsdata.ca/resource/K12-150"]]}
      actual = search_cckg "Emily D’Angelo", "Person"
      assert_equal expected, actual
    end
  end
  

  test "search_cckg: should match names with &" do  
    VCR.use_cassette('StatementsHelperSearchCckgTest: should match names with &') do
      expected = {:data=>[["meagan&amy", "http://kg.artsdata.ca/resource/K10-376"]]}
      actual = search_cckg "meagan&amp;amy", "Organization"
      assert_equal expected, actual
    end
  end

  test "search_cckg: should match places with title in French" do  
    VCR.use_cassette('StatementsHelperSearchCckgTest: should match places with title in French') do
      expected = {:data=>[["Théâtre Marc Lescarbot", "http://kg.artsdata.ca/resource/K11-133"]]}
      actual = search_cckg "Théâtre Marc Lescarbot", "Place"
      assert_equal expected, actual
    end
  end

  test "search_cckg: find alternate names" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: find alternate names') do
      expected = {data:[["Dow Centennial Centre - Shell Theatre", "http://kg.artsdata.ca/resource/K11-64"]]}
      actual = search_cckg "Shell Theatre", "Place"
      assert_equal expected, actual
    end
  end


  test "search_cckg: find additional type using artsdata" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: find additional types') do
      expected = {data:[["Dance", "http://kg.artsdata.ca/resource/DancePerformance"]]}
      actual = search_cckg("Dance", "EventType")
      assert_equal expected, actual
    end
  end

  test "search_cckg: structured reconciliation for place with QC province returns Montreal result only" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("QC")

    HTTParty.expects(:get).with do |url|
      url.include?("queries=") &&
        url.include?("schema%3Aaddress%2Fschema%3AaddressRegion") &&
        url.include?("%22v%22%3A%22QC%22")
    end.returns(
      {
        "q0" => {
          "result" => [
            { "id" => "K11-3", "name" => "Place des Arts", "match" => true, "score" => 95.0 }
          ]
        }
      }
    )

    expected = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-3"]] }
    actual = search_cckg("Place des Arts", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg: structured reconciliation for place with ON province returns Sudbury result only" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("ON")

    HTTParty.expects(:get).with do |url|
      url.include?("queries=") &&
        url.include?("schema%3Aaddress%2Fschema%3AaddressRegion") &&
        url.include?("%22v%22%3A%22ON%22")
    end.returns(
      {
        "q0" => {
          "result" => [
            { "id" => "K11-SUDBURY", "name" => "Place des Arts (Sudbury)", "match" => true, "score" => 96.0 }
          ]
        }
      }
    )

    expected = { data: [["Place des Arts (Sudbury)", "http://kg.artsdata.ca/resource/K11-SUDBURY"]] }
    actual = search_cckg("Place des Arts", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg: no province falls back to legacy extraction behavior and can return multiple results" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns(nil)

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      {
        "result" => [
          { "id" => "K11-3", "name" => "Place des Arts", "match" => true, "score" => 95.0 },
          { "id" => "K11-SUDBURY", "name" => "Place des Arts (Sudbury)", "match" => false, "score" => 70.0 }
        ]
      }
    )

    expected = {
      data: [
        ["Place des Arts", "http://kg.artsdata.ca/resource/K11-3"],
        ["Place des Arts (Sudbury)", "http://kg.artsdata.ca/resource/K11-SUDBURY"]
      ]
    }
    actual = search_cckg("Place des Arts", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg: clean query resolves to a single best match" do
    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      {
        "result" => [
          { "id" => "K11-3", "name" => "Place des Arts", "match" => true, "score" => 95.0 },
          { "id" => "K11-SUDBURY", "name" => "Place des Arts (Sudbury)", "match" => false, "score" => 70.0 }
        ]
      }
    )

    expected = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-3"]] }
    actual = search_cckg("Place des Arts", "Place")
    assert_equal expected, actual
  end

  test "search_cckg: noisy query uses extraction behavior and returns multiple matches" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("ON")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Bluma%20Appel%20Theatre%20and%20Berkeley%20Street%20Theatre") && url.include?("&type=Place")
    end.returns(
      {
        "result" => [
          { "id" => "K11-6", "name" => "St. Lawrence Centre for the Arts - Bluma Appel Theatre", "match" => false, "score" => 81.0 },
          { "id" => "K11-14", "name" => "Canadian Stage - Berkeley Street Theatre", "match" => false, "score" => 80.0 }
        ]
      }
    )

    expected = {
      data: [
        ["St. Lawrence Centre for the Arts - Bluma Appel Theatre", "http://kg.artsdata.ca/resource/K11-6"],
        ["Canadian Stage - Berkeley Street Theatre", "http://kg.artsdata.ca/resource/K11-14"]
      ]
    }
    actual = search_cckg("Bluma Appel Theatre and Berkeley Street Theatre", "Place", webpage)
    assert_equal expected, actual
  end

end
