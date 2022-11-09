require 'test_helper'

class LocalGraphGeneratorTest < ActiveSupport::TestCase
  test "generate a single graph of Places" do
    expected = 21
    actual = LocalGraphGenerator.graph_class('Place').count
    assert_equal expected, actual
  end

  test "generate all local graphs" do
    expected = 42
    actual = LocalGraphGenerator.graph_all.count
    assert_equal expected, actual
  end
end
