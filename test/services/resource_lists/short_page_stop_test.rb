# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/short_page_stop"

class ShortPageStopTest < Minitest::Test
  def stop?(previous, current)
    ResourceLists::ShortPageStop.stop?(previous_count: previous, current_count: current)
  end

  def test_hector_charland_stops_on_page_five_after_including_23_links
    assert stop?(42, 23)
  end

  def test_full_pages_do_not_stop
    refute stop?(42, 42)
  end

  def test_exactly_ninety_percent_does_not_stop
    refute stop?(10, 9)
  end

  def test_strictly_below_ninety_percent_stops
    assert stop?(42, 37)
    refute stop?(42, 38)
  end

  def test_empty_page_after_nonempty_page_stops
    assert stop?(42, 0)
  end

  def test_empty_previous_page_does_not_count_as_valid_short_page
    refute stop?(0, 0)
    refute stop?(0, 42)
  end

  def test_bad_counts_fail_closed
    assert_raises(ArgumentError) { stop?(42, nil) }
    assert_raises(ArgumentError) { stop?(-1, 0) }
    assert_raises(ArgumentError) { stop?(42, "0") }
  end
end
