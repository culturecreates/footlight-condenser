class JsonlUriWrapperTest < ActiveSupport::TestCase
  test "should extract one uri" do
    cache = '["source text", "Expected Class", [ "Entity label", "http://example.com" ]]'
    expected_output = ["http://example.com"]
    assert_equal expected_output, JsonlUriWrapper.extract_uris_from_cache(cache)
  end

  test "should extract two uris" do
    cache = '["source text", "Expected Class", [ "Entity 1", "http://example.com#1" ], [ "Entity 2", "http://example.com#2" ] ]'
    expected_output = ["http://example.com#1", "http://example.com#2"]
    assert_equal expected_output, JsonlUriWrapper.extract_uris_from_cache(cache)
  end

  test "should extract uri 3 and not the deleted uri 1" do
    cache = '[["text", "Class", [ "Entity 1", "http://example.com#1" ]],["text 3", "Class 3", [ "Entity 3", "http://example.com#3" ] ],["Manually deleted", "Class",["Label","http://example.com#1"]]]'
    expected_output = ["http://example.com#3"]
    assert_equal expected_output, JsonlUriWrapper.extract_uris_from_cache(cache)
  end

  test "should extract  uri 2 from double link and not the deleted uri 1" do
    cache = '[["source text", "Expected Class", [ "Entity 1", "http://example.com#1" ], [ "Entity 2", "http://example.com#2" ] ],["Manually deleted", "Class",["Label","http://example.com#1"]]]'
    expected_output = ["http://example.com#2"]
    assert_equal expected_output, JsonlUriWrapper.extract_uris_from_cache(cache)
  end

  test "build_json_from_anyURI simple case" do
    expected_output = [{:search=>"The Fredericton Playhouse", :class=>"Place", :links=>[{:label=>"The Fredericton Playhouse", :uri=>"http://kg.artsdata.ca/resource/11-62"}]}]
    input = "[\"The Fredericton Playhouse\", \"Place\", [\"The Fredericton Playhouse\", \"http://kg.artsdata.ca/resource/11-62\"]]"
    assert_equal expected_output, JsonlUriWrapper.build_json_from_anyURI(input)
  end

  test "build_json_from_anyURI multiple hits" do
    expected_output = [{:search=>"The Fredericton Playhouse", :class=>"Place", :links=>[{:label=>"Playhouse", :uri=>"http://kg.artsdata.ca/resource/11-62"},{:label=>"Playhouse 2", :uri=>"http://kg.artsdata.ca/resource/11-622"}]}]
    input = "[\"The Fredericton Playhouse\", \"Place\", [\"Playhouse\", \"http://kg.artsdata.ca/resource/11-62\"],[\"Playhouse 2\", \"http://kg.artsdata.ca/resource/11-622\"]]"
    assert_equal expected_output, JsonlUriWrapper.build_json_from_anyURI(input)
  end

  test "build_json_from_anyURI array in array" do
    expected_output = [{:search=>"Source", :class=>"Place", :links=>[{:label=>"Theatre", :uri=>"http://kg.artsdata.ca/resource/11-62"}]},{:search=>"Source2", :class=>"Place", :links=>[{:label=>"Theatre2", :uri=>"http://kg.artsdata.ca/resource/11-622"}]}]
    input = "[[\"Source\", \"Place\", [\"Theatre\", \"http://kg.artsdata.ca/resource/11-62\"]],[\"Source2\", \"Place\", [\"Theatre2\", \"http://kg.artsdata.ca/resource/11-622\"]]]"
    assert_equal expected_output, JsonlUriWrapper.build_json_from_anyURI(input)
  end

  test "build_json_from_anyURI array in array with multiple hits" do
    expected_output = [{:search=>"Playhouse", :class=>"Place", :links=>[{:label=>"Playhouse", :uri=>"http://kg.artsdata.ca/resource/11-62"},{:label=>"Playhouse 2", :uri=>"http://kg.artsdata.ca/resource/11-622"}]},{:search=>"Playhouse", :class=>"Place", :links=>[{:label=>"Playhouse", :uri=>"http://kg.artsdata.ca/resource/11-62"}]}]
    input = "[[\"Playhouse\", \"Place\", [\"Playhouse\", \"http://kg.artsdata.ca/resource/11-62\"],[\"Playhouse 2\", \"http://kg.artsdata.ca/resource/11-622\"]], [\"Playhouse\", \"Place\", [\"Playhouse\", \"http://kg.artsdata.ca/resource/11-62\"]]]"
    assert_equal expected_output, JsonlUriWrapper.build_json_from_anyURI(input)
  end

  test "build_json_from_anyURI array with abort" do
    expected_output = [{:search=>"", :class=>"Organization", :links=>[]}, {:search=>"", :class=>"Organization", :links=>[]}]
    input = "[[\"\", \"Organization\", \"abort_update\"], [\"\", \"Organization\", \"abort_update\"]]"
    assert_equal expected_output, JsonlUriWrapper.build_json_from_anyURI(input)
  end
end
