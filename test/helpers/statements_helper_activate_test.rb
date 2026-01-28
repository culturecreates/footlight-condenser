require 'test_helper'

# StatementsHelper tests for activate() only
class StatementsHelperActivateTest < ActionView::TestCase
  tests StatementsHelper


  test "activate_source_across_all_events() should activate source" do
       sources = activate_source(statements(:three))
       actual = sources.find { |s| s.id == statements(:three).source.id }.selected
       assert actual
  end
end