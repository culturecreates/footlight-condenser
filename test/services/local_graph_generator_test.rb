require 'test_helper'

class LocalGraphGeneratorTest < ActiveSupport::TestCase
  test "generate a single graph of Places" do
    graph = LocalGraphGenerator.graph_class('Place')
    # puts graph.dump(:turtle)
    expected = 6
    actual = graph.count
    assert_equal expected, actual
  end

  test "generate all local graphs" do
    expected = 12
    actual = LocalGraphGenerator.graph_all.count
    assert_equal expected, actual
  end
end
