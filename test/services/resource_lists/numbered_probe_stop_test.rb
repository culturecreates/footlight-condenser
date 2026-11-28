# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/numbered_probe_stop"

class NumberedProbeStopTest < Minitest::Test
  def reason(**overrides)
    options = { ajax_shell: false, challenge: false, repeated_content: false,
      repeated_links: false, short_page: false, next_link_observed: false,
      allow_heuristic_stop: false }
    ResourceLists::NumberedProbeStop.reason(**options.merge(overrides))
  end

  def test_co_motion_short_page_with_a_next_link_is_not_a_stop
    assert_nil reason(short_page: true, next_link_observed: true)
    assert_nil reason(short_page: true, next_link_observed: true, allow_heuristic_stop: true)
  end

  def test_short_page_without_next_link_is_advisory_by_default
    assert_nil reason(short_page: true)
  end

  def test_explicit_opt_in_enables_inconclusive_short_page_stop
    assert_equal "heuristic_short_page", reason(short_page: true, allow_heuristic_stop: true)
  end

  def test_absent_next_link_is_not_itself_a_stop
    assert_nil reason(next_link_observed: false)
  end

  def test_ajax_shell_is_a_hard_stop
    assert_equal "ajax_shell_requires_rendering", reason(ajax_shell: true)
  end

  def test_challenge_is_a_hard_stop
    assert_equal "challenge_page_detected", reason(challenge: true)
  end

  def test_exact_repeated_response_is_inconclusive_stop
    assert_equal "repeated_content", reason(repeated_content: true)
  end

  def test_repeated_link_inventory_is_inconclusive_stop
    assert_equal "repeated_link_inventory", reason(repeated_links: true)
  end

  def test_hard_stop_takes_priority_over_heuristic
    assert_equal "challenge_page_detected", reason(challenge: true,
      short_page: true, allow_heuristic_stop: true)
  end
end
