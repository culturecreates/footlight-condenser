require 'test_helper'

class RDFLoaderTest < ActiveSupport::TestCase
  # test method load_sparql
  test "should return sparql with ?o_ preferred" do
    assert RDFLoader.load_sparql('coalesce_languages.sparql').include?('coalesce(?o_placeholder,')
  end

  test 'should return sparql with ?o_fr preferred' do
    assert  RDFLoader.load_sparql('coalesce_languages.sparql', ['placeholder','fr']).include?('coalesce(?o_fr,')
  end

end
