require 'test_helper'

class ResourcesHelperTest < ActionView::TestCase


  test "build_json_from_anyURI simple case" do
    expected_output = [{:search=>"The Fredericton Playhouse", :class=>"Place", :links=>[{:label=>"The Fredericton Playhouse", :uri=>"http://kg.artsdata.ca/resource/11-62"}]}]
    input = "[\"The Fredericton Playhouse\", \"Place\", [\"The Fredericton Playhouse\", \"http://kg.artsdata.ca/resource/11-62\"]]"
    assert_equal expected_output, build_json_from_anyURI(input)
  end

  test "build_json_from_anyURI multiple hits" do
    expected_output = [{:search=>"The Fredericton Playhouse", :class=>"Place", :links=>[{:label=>"Playhouse", :uri=>"http://kg.artsdata.ca/resource/11-62"},{:label=>"Playhouse 2", :uri=>"http://kg.artsdata.ca/resource/11-622"}]}]
    input = "[\"The Fredericton Playhouse\", \"Place\", [\"Playhouse\", \"http://kg.artsdata.ca/resource/11-62\"],[\"Playhouse 2\", \"http://kg.artsdata.ca/resource/11-622\"]]"
    assert_equal expected_output, build_json_from_anyURI(input)
  end

  test "build_json_from_anyURI array in array" do
    expected_output = [{:search=>"Source", :class=>"Place", :links=>[{:label=>"Theatre", :uri=>"http://kg.artsdata.ca/resource/11-62"}]},{:search=>"Source2", :class=>"Place", :links=>[{:label=>"Theatre2", :uri=>"http://kg.artsdata.ca/resource/11-622"}]}]
    input = "[[\"Source\", \"Place\", [\"Theatre\", \"http://kg.artsdata.ca/resource/11-62\"]],[\"Source2\", \"Place\", [\"Theatre2\", \"http://kg.artsdata.ca/resource/11-622\"]]]"
    assert_equal expected_output, build_json_from_anyURI(input)
  end



  test "build_json_from_anyURI array in array with multiple hits" do
    expected_output = [{:search=>"Playhouse", :class=>"Place", :links=>[{:label=>"Playhouse", :uri=>"http://kg.artsdata.ca/resource/11-62"},{:label=>"Playhouse 2", :uri=>"http://kg.artsdata.ca/resource/11-622"}]},{:search=>"Playhouse", :class=>"Place", :links=>[{:label=>"Playhouse", :uri=>"http://kg.artsdata.ca/resource/11-62"}]}]
    input = "[[\"Playhouse\", \"Place\", [\"Playhouse\", \"http://kg.artsdata.ca/resource/11-62\"],[\"Playhouse 2\", \"http://kg.artsdata.ca/resource/11-622\"]], [\"Playhouse\", \"Place\", [\"Playhouse\", \"http://kg.artsdata.ca/resource/11-62\"]]]"
    assert_equal expected_output, build_json_from_anyURI(input)
  end




end
