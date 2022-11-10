require 'test_helper'

# StatementsHelper tests for search_cckg() only
class StatementsHelperSearchCckgTest < ActionView::TestCase
  tests StatementsHelper

  # search_condenser
  test "search_condenser: should search condenser for uris that match 100%" do
    expected = {:data=>[["Statement Six Name", "adr:seven"]]}
    actual = search_condenser("Statement Six Name", "Place")
    assert_equal expected, actual
  end

  test "search_condenser: should only match exact string" do
    expected = {:data=>[]} # ["Statement Six Name", "adr:seven"]
    actual = search_condenser("Statement Six", "Place")
    assert_equal expected, actual
  end

  # NOT POSSIBLE TO FIND SUBSTRINGS WITH REGULAR use of LIKE, need full text search
  # test "search_condenser: match substring in search string" do
  #   expected = {:data=>[["Statement Six Name", "adr:seven"]]}
  #   actual = search_condenser("Best place is Statement Six Name in Toronto", "Place")
  #   assert_equal expected, actual
  # end

  test "search_condenser: should search condenser for nowhere" do
    expected = {data:[]}
    actual = search_condenser("Show is at nowhere", "Place")
    assert_equal expected, actual
  end

  test "search_condenser: should find Amphitheatre Cogeco only" do
    expected = {data:[["Amphitheatre Cogeco", "adr:K11-1234"]]}
    actual = search_condenser("Amphitheatre Cogeco", "Place")
    assert_equal expected, actual
  end

  test "search_condenser: should find Person Louise when type is Organization" do
    expected = {data:[["Louise Antoinette", "adr:Louise-Antoinette"], ["Louise Antoinette", "adr:Louise-Antoinette-inc"]]}
    actual = search_condenser("Louise Antoinette", "Organization")
    assert_equal expected, actual
  end

end