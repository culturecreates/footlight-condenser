require 'test_helper'

# StatementsHelper tests for search_cckg() only
class StatementsHelperSearchCckgTest < ActionView::TestCase
  tests StatementsHelper

  test "search_cckg: should search cckg for uris that match 100%" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: should search cckg for uris that match 100%') do
      expected = {:data=>[["Place des Arts - Théâtre Maisonneuve", "http://kg.artsdata.ca/resource/K11-11"]]}
      actual = search_cckg "Théâtre Maisonneuve", "Place"
      assert_equal expected, actual
    end
  end

  test "search_cckg: should search cckg for uris by matching name in substring" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: should search cckg for uris by matching name in substring') do
      expected = {:data=>[["St. Lawrence Centre for the Arts - Bluma Appel Theatre", "http://kg.artsdata.ca/resource/K11-6"]]}
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
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "result" => [
            { "id" => "K11-3", "name" => "Place des Arts", "match" => true, "score" => 95.0 }
          ]
        }
      )
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
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "result" => [
            { "id" => "K11-SUDBURY", "name" => "Place des Arts (Sudbury)", "match" => true, "score" => 96.0 }
          ]
        }
      )
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

    expected = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-3"]] }
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

    expected = { data: [["St. Lawrence Centre for the Arts - Bluma Appel Theatre", "http://kg.artsdata.ca/resource/K11-6"]] }
    actual = search_cckg("Bluma Appel Theatre and Berkeley Street Theatre", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg: substring matching keeps noisy place hits with realistic Artsdata response" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("ON")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Bluma%20Appel%20Theatre%20and%20Berkeley%20Street%20Theatre") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "result" => [
            {
              "id" => "K11-6",
              "name" => "St. Lawrence Centre for the Arts - Bluma Appel Theatre",
              "type" => ["schema:Place"],
              "match" => false,
              "score" => 81.0
            },
            {
              "id" => "K11-14",
              "name" => "Canadian Stage - Berkeley Street Theatre",
              "type" => ["schema:Place"],
              "match" => false,
              "score" => 80.0
            }
          ]
        }.to_json
      )
    )

    expected = { data: [["St. Lawrence Centre for the Arts - Bluma Appel Theatre", "http://kg.artsdata.ca/resource/K11-6"]] }
    actual = search_cckg("Bluma Appel Theatre and Berkeley Street Theatre", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg: handling of ampersand matches HTML escaped query to Artsdata name" do
    HTTParty.expects(:get).with do |url|
      url.include?("?query=meagan%26amy") && url.include?("&type=Organization")
    end.returns(
      stub(
        body: {
          "result" => [
            {
              "id" => "K10-376",
              "name" => "meagan&amy",
              "type" => ["schema:Organization"],
              "match" => false,
              "score" => 99.0
            }
          ]
        }.to_json
      )
    )

    expected = { data: [["meagan&amy", "http://kg.artsdata.ca/resource/K10-376"]] }
    actual = search_cckg("meagan&amp;amy", "Organization")
    assert_equal expected, actual
  end

  test "search_cckg: duplicate removal keeps a single URI when Artsdata returns duplicate ids" do
    HTTParty.expects(:get).with do |url|
      url.include?("?query=Berkeley%20Street%20Theatre") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "result" => [
            {
              "id" => "K11-14",
              "name" => "Canadian Stage - Berkeley Street Theatre",
              "type" => ["schema:Place"],
              "match" => true,
              "score" => 99.0
            },
            {
              "id" => "K11-14",
              "name" => "Berkeley Street Theatre",
              "type" => ["schema:Place"],
              "match" => false,
              "score" => 92.0
            }
          ]
        }.to_json
      )
    )

    expected = { data: [["Berkeley Street Theatre", "http://kg.artsdata.ca/resource/K11-14"]] }
    actual = search_cckg("Berkeley Street Theatre", "Place")
    assert_equal expected, actual
  end

  test "search_cckg: clean filtering fallback returns best hit when filter removes all candidates" do
    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "result" => [
            {
              "id" => "K11-3",
              "name" => "Unrelated Place Name",
              "type" => ["schema:Place"],
              "match" => false,
              "score" => 95.0
            },
            {
              "id" => "K11-SUDBURY",
              "name" => "Another Unrelated Place",
              "type" => ["schema:Place"],
              "match" => false,
              "score" => 70.0
            }
          ]
        }.to_json
      )
    )

    expected = { data: [["Unrelated Place Name", "http://kg.artsdata.ca/resource/K11-3"]] }
    actual = search_cckg("Place des Arts", "Place")
    assert_equal expected, actual
  end

  test "search_cckg: improved reconciliation - single hit returns that hit" do
    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "result" => [
            {
              "id" => "K11-3",
              "name" => "Place des Arts",
              "addressRegion" => "QC",
              "match" => true,
              "score" => 98.0
            }
          ]
        }.to_json
      )
    )

    expected = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-3"]] }
    actual = search_cckg("Place des Arts", "Place")
    assert_equal expected, actual
  end

  test "search_cckg: improved reconciliation - Place des Arts across provinces prefers webpage province when multiple exact matches" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("QC")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "q0" => {
            "result" => [
              { "id" => "K11-MTL", "name" => "Place des Arts", "description" => "QC", "addressRegion" => "QC", "match" => true, "score" => 95.0 },
              { "id" => "K11-SUDBURY", "name" => "Place des Arts", "description" => "ON", "addressRegion" => "ON", "match" => true, "score" => 99.0 }
            ]
          }
        }.to_json,
        request: stub(last_uri: "http://api.artsdata.ca/recon")
      )
    )

    expected = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-MTL"]] }
    actual = search_cckg("Place des Arts", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg: improved reconciliation - Esplanade de la Place des Arts returns normalized exact match" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("QC")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Esplanade%20de%20la%20Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "q0" => {
            "result" => [
              { "id" => "K11-3", "name" => "Place des Arts", "addressRegion" => "QC", "match" => false, "score" => 98.0 },
              { "id" => "K11-ESPL", "name" => "Esplanade de la Place des Arts", "addressRegion" => "QC", "match" => false, "score" => 93.0 }
            ]
          }
        }.to_json,
        request: stub(last_uri: "http://api.artsdata.ca/recon")
      )
    )

    expected = { data: [["Esplanade de la Place des Arts", "http://kg.artsdata.ca/resource/K11-ESPL"]] }
    actual = search_cckg("Esplanade de la Place des Arts", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg: improved reconciliation - ambiguous names across provinces use province then highest score among similar matches" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("ON")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Grand%20Theatre") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "q0" => {
            "result" => [
              { "id" => "K11-QC", "name" => "Grand Theatre de Quebec", "addressRegion" => "QC", "match" => false, "score" => 97.0 },
              { "id" => "K11-LON", "name" => "Grand Theatre London", "addressRegion" => "ON", "match" => false, "score" => 89.0 },
              { "id" => "K11-TOR", "name" => "Grand Theatre Toronto", "addressRegion" => "ON", "match" => false, "score" => 91.0 }
            ]
          }
        }.to_json,
        request: stub(last_uri: "http://api.artsdata.ca/recon")
      )
    )

    expected = { data: [["Grand Theatre de Quebec", "http://kg.artsdata.ca/resource/K11-QC"]] }
    actual = search_cckg("Grand Theatre", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg: improved reconciliation - no province case returns highest score for ambiguous exact matches" do
    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "result" => [
            { "id" => "K11-MTL", "name" => "Place des Arts", "addressRegion" => "QC", "match" => true, "score" => 92.0 },
            { "id" => "K11-SUDBURY", "name" => "Place des Arts", "addressRegion" => "ON", "match" => true, "score" => 99.0 }
          ]
        }.to_json
      )
    )

    expected = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-SUDBURY"]] }
    actual = search_cckg("Place des Arts", "Place")
    assert_equal expected, actual
  end

  test "search_cckg: improved reconciliation - noisy partial names with province prefer local overlap over global score" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("ON")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=at%20the%20Place%20des%20Arts%20esplanade%20and%20tonight") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "result" => [
            { "id" => "K11-QC-ESPL", "name" => "Esplanade de la Place des Arts", "addressRegion" => "QC", "match" => false, "score" => 99.0 },
            { "id" => "K11-ON-PDA", "name" => "Place des Arts (Sudbury)", "addressRegion" => "ON", "match" => false, "score" => 85.0 },
            { "id" => "K11-ON-THEATRE", "name" => "Place des Arts Theatre", "addressRegion" => "ON", "match" => false, "score" => 83.0 }
          ]
        }.to_json
      )
    )

    expected = { data: [["Esplanade de la Place des Arts", "http://kg.artsdata.ca/resource/K11-QC-ESPL"]] }
    actual = search_cckg("at the Place des Arts esplanade and tonight", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg uses structured query when province present" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("QC")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "q0" => { "result" => [{ "id" => "K11-3", "name" => "Place des Arts", "score" => 95.0, "match" => true }] }
        }.to_json
      )
    )

    expected = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-3"]] }
    actual = search_cckg("Place des Arts", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg falls back to global query when no province" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns(nil)

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "result" => [{ "id" => "K11-3", "name" => "Place des Arts", "score" => 95.0, "match" => true }]
        }.to_json
      )
    )

    expected = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-3"]] }
    actual = search_cckg("Place des Arts", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg handles Hash response from HTTParty stub" do
    HTTParty.expects(:get).with do |url|
      url.include?("?query=Wajdi%20Mouawad") && url.include?("&type=Person")
    end.returns(
      {
        "result" => [
          { "id" => "K12-362", "name" => "Wajdi Mouawad", "score" => 99.0, "match" => true }
        ]
      }
    )

    expected = { data: [["Wajdi Mouawad", "http://kg.artsdata.ca/resource/K12-362"]] }
    actual = search_cckg("Wajdi Mouawad", "Person")
    assert_equal expected, actual
  end

  test "fetch_cckg_hits parses both HTTParty and Hash responses" do
    HTTParty.expects(:get).twice.returns(
      stub(body: { "result" => [{ "id" => "K11-3", "name" => "Place des Arts", "match" => true, "score" => 95.0 }] }.to_json),
      { "result" => [{ "id" => "K11-SUDBURY", "name" => "Place des Arts (Sudbury)", "match" => true, "score" => 90.0 }] }
    )

    response_from_httparty = fetch_cckg_hits("Place des Arts", "Place", nil, false)
    response_from_hash = fetch_cckg_hits("Place des Arts", "Place", nil, false)

    assert_equal "K11-3", response_from_httparty.first["id"]
    assert_equal "K11-SUDBURY", response_from_hash.first["id"]
  end

  test "search_cckg: logging includes input and hit counts with exact selection reason" do
    logger = TestLogCapture.new
    Rails.stubs(:logger).returns(logger)

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "result" => [
            { "id" => "K11-3", "name" => "Place des Arts", "addressRegion" => "QC", "match" => true, "score" => 95.0 },
            { "id" => "K11-SUDBURY", "name" => "Place des Arts (Sudbury)", "addressRegion" => "ON", "match" => false, "score" => 70.0 }
          ]
        }.to_json
      )
    )

    search_cckg("Place des Arts", "Place")

    assert logger.entries.any? { |m| m.include?("[CCKG][INPUT]") && m.include?("query=") && m.include?("class=Place") }
    assert logger.entries.any? { |m| m.include?("[CCKG][HITS]") && m.include?("total=2") }
    assert logger.entries.any? { |m| m.include?("[CCKG][SELECT]") && m.include?("reason=exact") }
  end

  test "search_cckg: logging includes province match count and province selection reason" do
    logger = TestLogCapture.new
    Rails.stubs(:logger).returns(logger)

    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("ON")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Grand%20Theatre") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "q0" => {
            "result" => [
              { "id" => "K11-QC", "name" => "Grand Theatre Quebec", "addressRegion" => "QC", "match" => false, "score" => 80.0 },
              { "id" => "K11-ON", "name" => "Grand Theatre Ontario", "addressRegion" => "ON", "match" => false, "score" => 90.0 }
            ]
          }
        }.to_json,
        request: stub(last_uri: "http://api.artsdata.ca/recon")
      )
    )

    search_cckg("Grand Theatre", "Place", webpage)

    assert logger.entries.any? { |m| m.include?("[CCKG][HITS]") && m.include?("total=2") }
    assert logger.entries.any? { |m| m.include?("[CCKG][SELECT]") && m.include?("reason=province") }
  end

  test "search_cckg: logging uses fallback_score reason when no exact or province match drives selection" do
    logger = TestLogCapture.new
    Rails.stubs(:logger).returns(logger)

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Grand%20Theatre") && url.include?("&type=Place")
    end.returns(
      stub(
        body: {
          "result" => [
            { "id" => "K11-QC", "name" => "Grand Theatre Quebec", "addressRegion" => "QC", "match" => false, "score" => 92.0 },
            { "id" => "K11-ON", "name" => "Grand Theatre Ontario", "addressRegion" => "ON", "match" => false, "score" => 80.0 }
          ]
        }.to_json
      )
    )

    search_cckg("Grand Theatre", "Place")

    assert logger.entries.any? { |m| m.include?("[CCKG][SELECT]") && m.include?("reason=fallback_score") }
  end

  test "search_cckg place resolution: exact match wins over province" do
    logger = TestLogCapture.new
    Rails.stubs(:logger).returns(logger)

    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("ON")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Esplanade%20de%20la%20Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "q0" => {
            "result" => [
              { "id" => "K11-ESPL", "name" => "Esplanade de la Place des Arts", "description" => "QC", "match" => false, "score" => 90.0 },
              { "id" => "K11-ON", "name" => "Place des Arts Centre", "description" => "ON", "match" => false, "score" => 95.0 }
            ]
          }
        }
      )
    )

    expected = { data: [["Esplanade de la Place des Arts", "http://kg.artsdata.ca/resource/K11-ESPL"]] }
    actual = search_cckg("Esplanade de la Place des Arts", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg place resolution: multiple exact matches province disambiguates QC to Montreal" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("QC")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "q0" => {
            "result" => [
              { "id" => "K11-MTL", "name" => "Place des Arts", "description" => "QC", "match" => true, "score" => 92.0 },
              { "id" => "K11-SUDBURY", "name" => "Place des Arts", "description" => "ON", "match" => true, "score" => 99.0 }
            ]
          }
        }
      )
    )

    expected = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-MTL"]] }
    actual = search_cckg("Place des Arts", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg place resolution: multiple exact matches province disambiguates ON to Sudbury" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("ON")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "q0" => {
            "result" => [
              { "id" => "K11-MTL", "name" => "Place des Arts", "description" => "QC", "match" => true, "score" => 92.0 },
              { "id" => "K11-SUDBURY", "name" => "Place des Arts", "description" => "ON", "match" => true, "score" => 99.0 }
            ]
          }
        }
      )
    )

    expected = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-SUDBURY"]] }
    actual = search_cckg("Place des Arts", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg place resolution: no exact match falls back to score" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("ON")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Grand%20Theatre%20District") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "q0" => {
            "result" => [
              { "id" => "K11-LOW", "name" => "Grand Theatre Annex", "description" => "ON", "match" => false, "score" => 45.0 },
              { "id" => "K11-HIGH", "name" => "Main Theatre Complex", "description" => "QC", "match" => false, "score" => 88.0 }
            ]
          }
        }
      )
    )

    expected = { data: [["Main Theatre Complex", "http://kg.artsdata.ca/resource/K11-HIGH"]] }
    actual = search_cckg("Grand Theatre District", "Place", webpage)
    assert_equal expected, actual
  end

  test "search_cckg place resolution logging markers are emitted" do
    logger = TestLogCapture.new
    Rails.stubs(:logger).returns(logger)

    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("QC")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "q0" => {
            "result" => [
              { "id" => "K11-MTL", "name" => "Place des Arts", "description" => "QC", "match" => true, "score" => 95.0 },
              { "id" => "K11-SUDBURY", "name" => "Place des Arts", "description" => "ON", "match" => true, "score" => 99.0 }
            ]
          }
        }
      )
    )

    search_cckg("Place des Arts", "Place", webpage)

    assert logger.entries.any? { |m| m.include?("[CCKG][RESOLVE]") }
    assert logger.entries.any? { |m| m.include?("[CCKG][EXACT]") }
    assert logger.entries.any? { |m| m.include?("[CCKG][PROVINCE]") }
    assert logger.entries.any? { |m| m.include?("[CCKG][FINAL]") }
  end

  test "deterministic place resolution exact beats province ON" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("ON")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Esplanade%20de%20la%20Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "q0" => {
            "result" => [
              { "id" => "K11-ESPL", "name" => "Esplanade de la Place des Arts", "description" => "QC", "score" => 88.0, "match" => false },
              { "id" => "K11-ON", "name" => "Place des Arts Hall", "description" => "ON", "score" => 95.0, "match" => false }
            ]
          }
        }
      )
    )

    expected = { data: [["Esplanade de la Place des Arts", "http://kg.artsdata.ca/resource/K11-ESPL"]] }
    assert_equal expected, search_cckg("Esplanade de la Place des Arts", "Place", webpage)
  end

  test "deterministic place resolution multiple exact province decides" do
    website_qc = stub
    website_qc.stubs(:respond_to?).with(:province).returns(true)
    website_qc.stubs(:province).returns("QC")
    website_qc.stubs(:city).returns(nil)
    webpage_qc = stub
    webpage_qc.stubs(:website).returns(website_qc)

    website_on = stub
    website_on.stubs(:respond_to?).with(:province).returns(true)
    website_on.stubs(:province).returns("ON")
    website_on.stubs(:city).returns(nil)
    webpage_on = stub
    webpage_on.stubs(:website).returns(website_on)

    HTTParty.expects(:get).twice.returns(
      httparty_response(
        {
          "q0" => {
            "result" => [
              { "id" => "K11-MTL", "name" => "Place des Arts", "description" => "QC", "score" => 92.0, "match" => true },
              { "id" => "K11-SUDBURY", "name" => "Place des Arts", "description" => "ON", "score" => 99.0, "match" => true }
            ]
          }
        }
      ),
      httparty_response(
        {
          "q0" => {
            "result" => [
              { "id" => "K11-MTL", "name" => "Place des Arts", "description" => "QC", "score" => 92.0, "match" => true },
              { "id" => "K11-SUDBURY", "name" => "Place des Arts", "description" => "ON", "score" => 99.0, "match" => true }
            ]
          }
        }
      )
    )

    expected_qc = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-MTL"]] }
    expected_on = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-SUDBURY"]] }
    assert_equal expected_qc, search_cckg("Place des Arts", "Place", webpage_qc)
    assert_equal expected_on, search_cckg("Place des Arts", "Place", webpage_on)
  end

  test "deterministic place resolution no exact falls back to score" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("ON")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Grand%20Theatre%20District") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "q0" => {
            "result" => [
              { "id" => "K11-LOW", "name" => "Theatre Annex", "description" => "ON", "score" => 40.0, "match" => false },
              { "id" => "K11-HIGH", "name" => "Main Civic Auditorium", "description" => "QC", "score" => 82.0, "match" => false }
            ]
          }
        }
      )
    )

    expected = { data: [["Main Civic Auditorium", "http://kg.artsdata.ca/resource/K11-HIGH"]] }
    assert_equal expected, search_cckg("Grand Theatre District", "Place", webpage)
  end

  test "deterministic place resolution emits structured narrowing markers" do
    logger = TestLogCapture.new
    Rails.stubs(:logger).returns(logger)

    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("QC")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "q0" => {
            "result" => [
              { "id" => "K11-MTL", "name" => "Place des Arts", "description" => "QC", "score" => 92.0, "match" => true },
              { "id" => "K11-SUDBURY", "name" => "Place des Arts", "description" => "ON", "score" => 99.0, "match" => true }
            ]
          }
        }
      )
    )

    search_cckg("Place des Arts", "Place", webpage)

    assert logger.entries.any? { |m| m.include?("[CCKG][RESOLVE]") }
    assert logger.entries.any? { |m| m.include?("[CCKG][EXACT]") }
    assert logger.entries.any? { |m| m.include?("[CCKG][PROVINCE]") }
    assert logger.entries.any? { |m| m.include?("[CCKG][FINAL]") }
  end

  test "deterministic place resolution uses global fetch and exact beats province" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("ON")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Esplanade%20de%20la%20Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "result" => [
            { "id" => "K11-ESPL", "name" => "Esplanade de la Place des Arts", "description" => "QC", "score" => 88.0, "match" => false },
            { "id" => "K11-ON", "name" => "Place des Arts Hall", "description" => "ON", "score" => 95.0, "match" => false }
          ]
        }
      )
    )

    expected = { data: [["Esplanade de la Place des Arts", "http://kg.artsdata.ca/resource/K11-ESPL"]] }
    assert_equal expected, search_cckg("Esplanade de la Place des Arts", "Place", webpage)
  end

  test "deterministic place resolution uses global fetch and province disambiguates exact matches" do
    website_qc = stub
    website_qc.stubs(:respond_to?).with(:province).returns(true)
    website_qc.stubs(:province).returns("QC")
    website_qc.stubs(:city).returns(nil)
    webpage_qc = stub
    webpage_qc.stubs(:website).returns(website_qc)

    website_on = stub
    website_on.stubs(:respond_to?).with(:province).returns(true)
    website_on.stubs(:province).returns("ON")
    website_on.stubs(:city).returns(nil)
    webpage_on = stub
    webpage_on.stubs(:website).returns(website_on)

    HTTParty.expects(:get).twice.with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "result" => [
            { "id" => "K11-MTL", "name" => "Place des Arts", "description" => "QC", "score" => 92.0, "match" => true },
            { "id" => "K11-SUDBURY", "name" => "Place des Arts", "description" => "ON", "score" => 99.0, "match" => true }
          ]
        }
      ),
      httparty_response(
        {
          "result" => [
            { "id" => "K11-MTL", "name" => "Place des Arts", "description" => "QC", "score" => 92.0, "match" => true },
            { "id" => "K11-SUDBURY", "name" => "Place des Arts", "description" => "ON", "score" => 99.0, "match" => true }
          ]
        }
      )
    )

    expected_qc = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-MTL"]] }
    expected_on = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-SUDBURY"]] }
    assert_equal expected_qc, search_cckg("Place des Arts", "Place", webpage_qc)
    assert_equal expected_on, search_cckg("Place des Arts", "Place", webpage_on)
  end

  test "deterministic place resolution uses global fetch and falls back to score without exacts" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("ON")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Some%20fuzzy%20name") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "result" => [
            { "id" => "K11-LOW", "name" => "Small Hall", "description" => "ON", "score" => 40.0, "match" => false },
            { "id" => "K11-HIGH", "name" => "Main Civic Auditorium", "description" => "QC", "score" => 82.0, "match" => false }
          ]
        }
      )
    )

    expected = { data: [["Main Civic Auditorium", "http://kg.artsdata.ca/resource/K11-HIGH"]] }
    assert_equal expected, search_cckg("Some fuzzy name", "Place", webpage)
  end

  test "deterministic place resolution global path emits resolve markers" do
    logger = TestLogCapture.new
    Rails.stubs(:logger).returns(logger)

    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:province).returns("QC")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "result" => [
            { "id" => "K11-MTL", "name" => "Place des Arts", "description" => "QC", "score" => 92.0, "match" => true },
            { "id" => "K11-SUDBURY", "name" => "Place des Arts", "description" => "ON", "score" => 99.0, "match" => true }
          ]
        }
      )
    )

    search_cckg("Place des Arts", "Place", webpage)

    assert logger.entries.any? { |m| m.include?("[CCKG][RESOLVE]") }
    assert logger.entries.any? { |m| m.include?("[CCKG][EXACT]") }
    assert logger.entries.any? { |m| m.include?("[CCKG][PROVINCE]") }
    assert logger.entries.any? { |m| m.include?("[CCKG][FINAL]") }
  end

  test "deterministic place resolution uses locality after province tie" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:respond_to?).with(:city).returns(true)
    webpage.website.stubs(:province).returns("ON")
    webpage.website.stubs(:city).returns("Sudbury")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "result" => [
            { "id" => "K11-TOR", "name" => "Place des Arts", "description" => "Toronto ON", "score" => 99.0, "match" => true },
            { "id" => "K11-SUDBURY", "name" => "Place des Arts", "description" => "Sudbury ON", "score" => 92.0, "match" => true }
          ]
        }
      )
    )

    expected = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-SUDBURY"]] }
    assert_equal expected, search_cckg("Place des Arts", "Place", webpage)
  end

  test "deterministic place resolution exact ambiguity without province or locality falls back to highest score" do
    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:respond_to?).with(:city).returns(true)
    webpage.website.stubs(:province).returns(nil)
    webpage.website.stubs(:city).returns(nil)

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "result" => [
            { "id" => "K11-MTL", "name" => "Place des Arts", "description" => "Montreal QC", "score" => 92.0, "match" => true },
            { "id" => "K11-SUDBURY", "name" => "Place des Arts", "description" => "Sudbury ON", "score" => 99.0, "match" => true }
          ]
        }
      )
    )

    expected = { data: [["Place des Arts", "http://kg.artsdata.ca/resource/K11-SUDBURY"]] }
    assert_equal expected, search_cckg("Place des Arts", "Place", webpage)
  end

  test "deterministic place resolution emits locality marker when locality narrowing runs" do
    logger = TestLogCapture.new
    Rails.stubs(:logger).returns(logger)

    webpage = webpages(:four)
    webpage.website.stubs(:respond_to?).with(:province).returns(true)
    webpage.website.stubs(:respond_to?).with(:city).returns(true)
    webpage.website.stubs(:province).returns("ON")
    webpage.website.stubs(:city).returns("Sudbury")

    HTTParty.expects(:get).with do |url|
      url.include?("?query=Place%20des%20Arts") && url.include?("&type=Place")
    end.returns(
      httparty_response(
        {
          "result" => [
            { "id" => "K11-TOR", "name" => "Place des Arts", "description" => "Toronto ON", "score" => 99.0, "match" => true },
            { "id" => "K11-SUDBURY", "name" => "Place des Arts", "description" => "Sudbury ON", "score" => 92.0, "match" => true }
          ]
        }
      )
    )

    search_cckg("Place des Arts", "Place", webpage)

    assert logger.entries.any? { |m| m.include?("[CCKG][RESOLVE]") }
    assert logger.entries.any? { |m| m.include?("[CCKG][EXACT]") }
    assert logger.entries.any? { |m| m.include?("[CCKG][PROVINCE]") }
    assert logger.entries.any? { |m| m.include?("[CCKG][LOCALITY]") }
    assert logger.entries.any? { |m| m.include?("[CCKG][FINAL]") }
  end

  def httparty_response(body_hash, uri: "http://localhost:3003/recon")
    stub(
      body: body_hash.to_json,
      request: stub(last_uri: uri)
    )
  end

  class TestLogCapture
    attr_reader :entries

    def initialize
      @entries = []
    end

    def debug(message = nil, &block)
      @entries << (message || block&.call).to_s
    end

    def warn(message = nil, &block)
      @entries << (message || block&.call).to_s
    end

    def error(message = nil, &block)
      @entries << (message || block&.call).to_s
    end
  end

end
