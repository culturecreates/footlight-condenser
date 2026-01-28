require 'test_helper'

class RdfLoaderTest < ActiveSupport::TestCase
  # test method load_sparql
  test "should return sparql with ?o_ preferred" do
    assert_includes RdfLoader.load_sparql('coalesce_languages.sparql'), 'coalesce(?o_placeholder,'
  end

  test 'should return sparql with ?o_fr preferred' do
    assert_includes  RdfLoader.load_sparql('coalesce_languages.sparql', ['placeholder','fr']), 'coalesce(?o_fr,'
  end

end
