# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/numbered_page_query"
require_relative "../../../app/services/resource_lists/labeled_next_evidence"

class LabeledNextEvidenceTest < Minitest::Test
  BASE = "https://www.tourismeshawinigan.com/evenements/?search_query&categories%5B0%5D=culture&page=1"

  def setup
    @pages = ResourceLists::NumberedPageQuery.new(start_url: BASE)
  end

  def inspect(links, page: 8)
    ResourceLists::LabeledNextEvidence.call(anchors: links, pagination: @pages,
      page:, base_url: @pages.url_for(page))
  end

  def anchor(url, text: nil, aria: nil, title: nil, rel: nil)
    { href: url, text:, aria_label: aria, title:, rel: }
  end

  def test_semantically_labeled_next_to_nine
    result = inspect([anchor(@pages.url_for(7), text: "PRÉCÉDENTS ÉVÉNEMENTS"),
      anchor(@pages.url_for(9), text: "PROCHAINS ÉVÉNEMENTS")])
    assert_equal "labeled_forward_observed", result.status
    assert_equal @pages.url_for(9), result.labeled_next_url
    assert result.numbered_forward_link_seen
  end

  def test_nested_text_with_whitespace_and_diacritics
    result = inspect([anchor(@pages.url_for(9), text: "\n Prochains \t Événements \n")])
    assert_equal "labeled_forward_observed", result.status
  end

  def test_rel_next_and_aria_labels
    assert_equal "labeled_forward_observed", inspect([anchor(@pages.url_for(9), rel: "nofollow NEXT")]).status
    assert_equal "labeled_forward_observed", inspect([anchor(@pages.url_for(9), aria: "Page suivante")]).status
    assert_equal "labeled_forward_observed", inspect([anchor(@pages.url_for(9), title: "Next events")]).status
  end

  def test_numbered_link_without_semantic_label_is_not_labeled_next
    result = inspect([anchor(@pages.url_for(9), text: "9")])
    assert_equal "numbered_forward_only", result.status
    assert_nil result.labeled_next_url
    assert result.numbered_forward_link_seen
  end

  def test_last_page_with_only_backward_link_is_not_complete_proof
    result = inspect([anchor(@pages.url_for(8), text: "PRÉCÉDENTS ÉVÉNEMENTS")], page: 9)
    assert_equal "no_forward_observed", result.status
    refute result.numbered_forward_link_seen
    refute result.respond_to?(:complete?)
  end

  def test_page_ten_backward_link_still_not_completeness_proof
    result = inspect([anchor(@pages.url_for(9), text: "Précédents événements")], page: 10)
    assert_equal "no_forward_observed", result.status
  end

  def test_wrong_filter_labeled_link_is_a_conflict
    bad = @pages.url_for(9).sub("culture", "theatre")
    result = inspect([anchor(bad, text: "Prochains événements"), anchor(@pages.url_for(9), text: "9")])
    assert_equal "inconclusive_labeled_target_conflict", result.status
    assert_equal [bad], result.invalid_labeled_targets
    assert_nil result.labeled_next_url
  end

  def test_labeled_fragment_link_is_a_conflict
    result = inspect([anchor("#next", text: "Prochains événements")])
    assert_equal "inconclusive_labeled_target_conflict", result.status
  end

  def test_labeled_external_url_is_a_conflict
    result = inspect([anchor("https://evil.example/events?page=9", text: "Next events")])
    assert_equal "inconclusive_labeled_target_conflict", result.status
  end

  def test_labeled_non_next_page_is_a_conflict
    result = inspect([anchor(@pages.url_for(7), text: "Prochains événements")])
    assert_equal "inconclusive_labeled_target_conflict", result.status
  end

  def test_unrelated_next_page_navigation_elsewhere_is_a_conflict
    result = inspect([anchor("/different?page=9", text: "Next")])
    assert_equal "inconclusive_labeled_target_conflict", result.status
  end

  def test_malformed_link_is_ignored_unless_labeled
    result = inspect([anchor("http://[invalid", text: "Some label"), anchor(@pages.url_for(9), text: "9")])
    assert_equal "numbered_forward_only", result.status
    result = inspect([anchor("http://[invalid", text: "Prochains événements")])
    assert_equal "inconclusive_labeled_target_conflict", result.status
  end

  def test_missing_href_on_labeled_anchor_is_a_conflict
    result = inspect([{ text: "Prochains événements" }])
    assert_equal "inconclusive_labeled_target_conflict", result.status
  end

  def test_changed_query_bare_key_does_not_affect_valid_next
    result = inspect([anchor(@pages.url_for(9), text: "Prochains événements")])
    assert_includes result.labeled_next_url, "?search_query&categories%5B0%5D=culture&page=9"
  end
end
