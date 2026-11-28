# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/numbered_page_label"

class NumberedPageLabelTest < Minitest::Test
  def check(str, page: 2)
    ResourceLists::NumberedPageLabel.call(text: str, expected_page: page)
  end

  def test_lpdv_french_label
    result = check("Dans un rayon de 100 km de Montréal • Page 2 de 75")
    assert result.observed?
    assert_equal 2, result.page
    assert_equal 75, result.last_page
    assert_empty result.errors
  end

  def test_whitespace_and_case
    result = check("PAGE\n 2 \t de   9")
    assert result.observed?
    assert_equal 9, result.last_page
  end

  def test_repeated_same_label_is_not_ambiguous
    result = check("Page 2 de 9 ... Page 2 de 9")
    assert result.observed?
    assert_equal 9, result.last_page
  end

  def test_conflicting_labels_are_inconclusive
    result = check("Page 2 de 9 and Page 2 de 10")
    refute result.observed?
    assert_includes result.errors, "ambiguous_page_labels"
  end

  def test_mismatched_page_is_inconclusive
    assert_includes check("Page 3 de 9").errors, "requested_page_mismatch"
  end

  def test_missing_label_is_inconclusive
    assert_includes check("2 / 9").errors, "missing_page_label"
  end

  def test_bad_bounds_fail_closed
    assert_includes check("Page 0 de 9").errors, "invalid_page_range"
    assert_includes check("Page 10 de 9", page: 10).errors, "invalid_page_range"
  end

  def test_invalid_expected_page_or_text_fails_closed
    assert_includes check("Page 2 de 9", page: 0).errors, "invalid_expected_page"
    assert_includes check(nil).errors, "missing_text"
  end

  def test_does_not_claim_authoritative_completeness
    refute check("Page 2 de 9").respond_to?(:complete?)
  end
end
