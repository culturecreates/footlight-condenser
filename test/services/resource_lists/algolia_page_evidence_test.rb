# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/algolia_page_evidence"

class AlgoliaPageEvidenceTest < Minitest::Test
  def response(page: 1, nb_pages: 5, size: 21, hits: 105, records: [{ "objectID" => "x" }])
    { "page" => page, "nbPages" => nb_pages, "hitsPerPage" => size, "nbHits" => hits, "hits" => records }
  end

  def evidence(data: response, page: 1, index: "PDA-production-fr-clone", slot: true, status: 200)
    ResourceLists::AlgoliaPageEvidence.call(response: data, requested_api_page: page,
      expected_index: "PDA-production-fr-clone", request_index: index, response_slot_verified: slot,
      http_status: status)
  end

  def test_forward_from_confirmed_api_metadata
    result = evidence
    assert_equal "forward_observed_by_metadata", result.status
    assert_equal 2, result.next_api_page
    assert_equal 4, result.last_accessible_api_page
    refute result.limit_suspected
  end

  def test_last_page_is_accessible_window_candidate_only
    result = evidence(data: response(page: 4), page: 4)
    assert_equal "last_accessible_page_candidate", result.status
    assert_nil result.next_api_page
    refute result.respond_to?(:complete?)
  end

  def test_more_hits_than_browsable_window_detected
    result = evidence(data: response(page: 3, nb_pages: 4, size: 250, hits: 1500), page: 3)
    assert_equal "last_accessible_page_candidate", result.status
    assert result.limit_suspected
  end

  def test_index_and_multiquery_slot_must_be_verified
    assert_equal "inconclusive", evidence(index: "other-index").status
    assert_equal "inconclusive", evidence(slot: false).status
  end

  def test_failed_requests_are_inconclusive
    assert_equal "inconclusive", evidence(status: 429).status
  end

  def test_api_page_is_not_assumed_from_routed_ui_page
    assert_equal "inconclusive", evidence(data: response(page: 0), page: 1).status
  end

  def test_invalid_or_missing_metadata_inconclusive
    assert_equal "inconclusive", evidence(data: response.reject { |k, _| k == "nbPages" }).status
    assert_equal "inconclusive", evidence(data: response(size: nil)).status
    assert_equal "inconclusive", evidence(data: response(nb_pages: 100)).status
  end

  def test_empty_search_is_candidate_not_full_completeness
    result = evidence(data: response(page: 0, nb_pages: 0, hits: 0, records: []), page: 0)
    assert_equal "no_hits_candidate", result.status
    assert_nil result.last_accessible_api_page
  end
end
