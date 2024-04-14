class JsonUriWrapperTest < ActiveSupport::TestCase
  test "should extract one uri" do
    cache = [{ search: "source text", class: "Expected Class", links: [ {label: "Entity label 1",uri: "URI1" }] }]
  
    expected_output = ["URI1"]
    assert_equal expected_output, JsonUriWrapper.extract_uris_from_cache(cache)
  end

  test "should extract two uris" do
    cache = [{ search: "source text", class: "Expected Class", links: [ {label: "Entity label 1",uri: "URI1" }, {label: "Entity label 2",uri: "URI2" }] }]
    #cache = ["source text", "Expected Class", [ "Entity 1", "http://example.com#1" ], [ "Entity 2", "http://example.com#2" ] ]
    expected_output = ["URI1", "URI2"]
    assert_equal expected_output, JsonUriWrapper.extract_uris_from_cache(cache)
  end

  test "should extract uri 3 and not the deleted uri 1" do
    cache = [{ search: "source text", class: "Expected Class", links: [ {label: "Entity label 1",uri: "URI1" }] }, { search: "source text 9", class: "Expected Class 9", links: [ {label: "Entity label",uri: "URI3" }] },  { search: "Manually deleted", class: "Expected Class 9", links: [ {label: "Entity label",uri: "URI1" }] }] 
 
    #cache = '[["text", "Class", [ "Entity 1", "http://example.com#1" ]],["text 3", "Class 3", [ "Entity 3", "http://example.com#3" ] ],["Manually deleted", "Class",["Label","http://example.com#1"]]]'
    expected_output = ["URI3"]
    assert_equal expected_output, JsonUriWrapper.extract_uris_from_cache(cache)
  end

  test "should extract  uri 2 from double link and not the deleted uri 1" do
    #cache = '[["source text", "Expected Class", [ "Entity 1", "http://example.com#1" ], [ "Entity 2", "http://example.com#2" ] ],["Manually deleted", "Class",["Label","http://example.com#1"]]]'
    cache = [{ search: "source text", class: "Expected Class", links: [ {label: "Entity label 1",uri: "URI1" }, {label: "Entity label 2",uri: "URI2" }] }, { search: "Manually deleted", class: "Expected Class 9", links: [ {label: "Entity label",uri: "URI1" }] }]
 
    expected_output = ["URI2"]
    assert_equal expected_output, JsonUriWrapper.extract_uris_from_cache(cache)
  end

  test "build_json_from_anyURI simple case" do
    expected_output = [{:search=>"The Fredericton Playhouse", :class=>"Place", :links=>[{:label=>"The Fredericton Playhouse", :uri=>"http://kg.artsdata.ca/resource/11-62"}]}]
    input = "[\"The Fredericton Playhouse\", \"Place\", [\"The Fredericton Playhouse\", \"http://kg.artsdata.ca/resource/11-62\"]]"
    assert_equal expected_output, JsonUriWrapper.build_json_from_anyURI(input)
  end

  test "build_json_from_anyURI multiple hits" do
    expected_output = [{:search=>"The Fredericton Playhouse", :class=>"Place", :links=>[{:label=>"Playhouse", :uri=>"http://kg.artsdata.ca/resource/11-62"},{:label=>"Playhouse 2", :uri=>"http://kg.artsdata.ca/resource/11-622"}]}]
    input = "[\"The Fredericton Playhouse\", \"Place\", [\"Playhouse\", \"http://kg.artsdata.ca/resource/11-62\"],[\"Playhouse 2\", \"http://kg.artsdata.ca/resource/11-622\"]]"
    assert_equal expected_output, JsonUriWrapper.build_json_from_anyURI(input)
  end

  test "build_json_from_anyURI array in array" do
    expected_output = [{:search=>"Source", :class=>"Place", :links=>[{:label=>"Theatre", :uri=>"http://kg.artsdata.ca/resource/11-62"}]},{:search=>"Source2", :class=>"Place", :links=>[{:label=>"Theatre2", :uri=>"http://kg.artsdata.ca/resource/11-622"}]}]
    input = "[[\"Source\", \"Place\", [\"Theatre\", \"http://kg.artsdata.ca/resource/11-62\"]],[\"Source2\", \"Place\", [\"Theatre2\", \"http://kg.artsdata.ca/resource/11-622\"]]]"
    assert_equal expected_output, JsonUriWrapper.build_json_from_anyURI(input)
  end

  test "build_json_from_anyURI array in array with multiple hits" do
    expected_output = [{:search=>"Playhouse", :class=>"Place", :links=>[{:label=>"Playhouse", :uri=>"http://kg.artsdata.ca/resource/11-62"},{:label=>"Playhouse 2", :uri=>"http://kg.artsdata.ca/resource/11-622"}]},{:search=>"Playhouse", :class=>"Place", :links=>[{:label=>"Playhouse", :uri=>"http://kg.artsdata.ca/resource/11-62"}]}]
    input = "[[\"Playhouse\", \"Place\", [\"Playhouse\", \"http://kg.artsdata.ca/resource/11-62\"],[\"Playhouse 2\", \"http://kg.artsdata.ca/resource/11-622\"]], [\"Playhouse\", \"Place\", [\"Playhouse\", \"http://kg.artsdata.ca/resource/11-62\"]]]"
    assert_equal expected_output, JsonUriWrapper.build_json_from_anyURI(input)
  end

  test "build_json_from_anyURI array with abort" do
    expected_output = [{:search=>"", :class=>"Organization", :links=>[]}, {:search=>"", :class=>"Organization", :links=>[]}]
    input = "[[\"\", \"Organization\", \"abort_update\"], [\"\", \"Organization\", \"abort_update\"]]"
    assert_equal expected_output, JsonUriWrapper.build_json_from_anyURI(input)
  end
  test "build_json_from_anyURI with nil" do
    expected_output = []
    input = nil
    assert_equal expected_output, JsonUriWrapper.build_json_from_anyURI(input)
  end

  test "check_for_multiple_missing_links simple case is false" do 
    expected_output = false
    input = '["Parc de Neuville", "Place", ["Parc de Neuville", "http://example.com/123"]]'
    assert_equal expected_output, JsonUriWrapper.check_for_multiple_missing_links(input)
  end

  test "check_for_multiple_missing_links bad URI is true" do 
    expected_output = true
    input = '["Parc de Neuville", "Place", ["Parc de Neuville", "example.com/123"]]'
    assert_equal expected_output, JsonUriWrapper.check_for_multiple_missing_links(input)
  end

  test "check_for_multiple_missing_links false" do 
    expected_output = false
    input = '[["Parc de Neuville", "Place", ["Parc de Neuville", "footlight:cd2df386-bf9c-4624-a468-56daa91d4c2b"]], ["Parc Jack-Eyamie", "Place", ["Parc Jack-Eyamie", "footlight:e188af8e-0ba9-4681-b443-a3e7ffeba39b"]], ["Manually added", "Place", ["Parc de Neuville", "footlight:cd2df386-bf9c-4624-a468-56daa91d4c2b"], ["Parc Jack-Eyamie", "footlight:e188af8e-0ba9-4681-b443-a3e7ffeba39b"]]]'
    assert_equal expected_output, JsonUriWrapper.check_for_multiple_missing_links(input)
  end

  test "check_for_multiple_missing_links is true" do 
    expected_output = true
    input = '["Lac Beauchamp", "Place"]'
    assert_equal expected_output, JsonUriWrapper.check_for_multiple_missing_links(input)
  end
  
  test "check_for_multiple_missing_links missing first is true" do 
    expected_output = true
    input = '[["Parc de Neuville", "Place"], ["Parc Jack-Eyamie", "Place", ["Parc Jack-Eyamie", "footlight:e188af8e-0ba9-4681-b443-a3e7ffeba39b"]], ["Manually added", "Place", ["Parc de Neuville", "footlight:cd2df386-bf9c-4624-a468-56daa91d4c2b"], ["Parc Jack-Eyamie", "footlight:e188af8e-0ba9-4681-b443-a3e7ffeba39b"]]]'
    assert_equal expected_output, JsonUriWrapper.check_for_multiple_missing_links(input)
  end

  test "check_for_multiple_missing_links in double array is true" do 
    expected_output = true
    input = '[["Lac Beauchamp", "Place"]]'
    assert_equal expected_output, JsonUriWrapper.check_for_multiple_missing_links(input)
  end

  test "check_for_multiple_missing_links is false with manually added single place" do 
    expected_output = false
    input = '[["Parc du 8 octobre 1906", "Place"],["Parc du 8 octobre 1906", "Place"], ["Parc du 8 octobre 1906", "Place"], ["Manually added", "Place", ["Parc du 8 octobre", "footlight:1ab78ede-28b4-4f7a-80c9-78023e75cbe1"]]]'
    assert_equal expected_output, JsonUriWrapper.check_for_multiple_missing_links(input)
  end

  test "invalid_uri is false" do
    assert_equal false, JsonUriWrapper.invalid_uri?("http://example.com")
  end

  test "invalid_uri" do
    assert_equal true, JsonUriWrapper.invalid_uri?("example.com")
  end

  test "invalid_uri when empty" do
    assert_equal true, JsonUriWrapper.invalid_uri?("")
  end

end
