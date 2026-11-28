# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/signe_laval_page_evidence"

class SigneLavalPageEvidenceTest < Minitest::Test
  def receipt(page: 10, count: 12, total: 185, size: 12, last: 16, is_last: false)
    JSON.generate({ "items" => count.times.map { |i| { "id" => "id-#{page}-#{i}" } },
      "pagination" => { "page" => page, "per_page" => size, "count" => count,
        "total" => total, "last_page" => last, "is_last" => is_last } })
  end

  def inspect_json(raw, page: 10, count: 12)
    ResourceLists::SigneLavalPageEvidence.call(body: raw, requested_page: page, requested_per_page: count)
  end

  def test_supplied_page_ten_metadata
    r = inspect_json(receipt)
    assert r.valid_page?
    assert_equal 12, r.count
    assert_equal 185, r.total
    assert_equal 16, r.last_page
    assert_equal false, r.is_last
    assert_empty r.warnings
    refute r.respond_to?(:complete?)
  end

  def test_hypothetical_sparse_page_is_advisory_only
    r = inspect_json(receipt(page: 6, count: 6), page: 6)
    assert r.valid_page?
    assert_includes r.warnings, "sparse_nonterminal_page"
    assert_equal 16, r.last_page
    assert_equal false, r.is_last
  end

  def test_actual_page_six_metadata_is_full
    r = inspect_json(receipt(page: 6, count: 12), page: 6)
    assert r.valid_page?
    assert_equal 12, r.item_ids.length
    assert_empty r.warnings
  end

  def test_final_page_with_five_items_is_valid
    r = inspect_json(receipt(page: 16, count: 5, is_last: true), page: 16)
    assert r.valid_page?
    assert_empty r.warnings
  end

  def test_mismatched_requested_page_is_rejected
    assert_includes inspect_json(receipt, page: 16).errors, "requested_page_mismatch"
  end

  def test_mismatched_requested_per_page_is_rejected
    assert_includes inspect_json(receipt, count: 24).errors, "requested_page_size_mismatch"
  end

  def test_count_must_equal_items_length
    raw = JSON.parse(receipt)
    raw["pagination"]["count"] = 11
    assert_includes inspect_json(JSON.generate(raw)).errors, "count_items_mismatch"
  end

  def test_no_duplicate_ids_in_one_page
    raw = JSON.parse(receipt)
    raw["items"][1]["id"] = raw["items"][0]["id"]
    assert_includes inspect_json(JSON.generate(raw)).errors, "duplicate_item_id"
  end

  def test_missing_item_id_is_rejected
    raw = JSON.parse(receipt)
    raw["items"][0].delete("id")
    assert_includes inspect_json(JSON.generate(raw)).errors, "missing_item_id"
  end

  def test_incorrect_last_page_metadata_is_rejected
    assert_includes inspect_json(receipt(last: 14)).errors, "incorrect_last_page"
  end

  def test_false_last_flag_on_final_page_is_rejected
    assert_includes inspect_json(receipt(page: 16, count: 5), page: 16).errors, "incorrect_is_last"
  end

  def test_true_last_flag_before_last_page_is_rejected
    assert_includes inspect_json(receipt(is_last: true)).errors, "incorrect_is_last"
  end

  def test_invalid_json_and_missing_fields_fail_closed
    assert_includes inspect_json("{oops").errors, "invalid_json"
    assert_includes inspect_json('{}').errors, "invalid_envelope"
    assert_includes inspect_json('{"items":[],"pagination":{"page":1}}').errors, "invalid_pagination_metadata"
  end

  def test_empty_total_fails_closed
    assert_includes inspect_json(receipt(page: 1, count: 0, total: 0, last: 1, is_last: true), page: 1).errors,
      "empty_calendar_unverified"
  end

  def test_non_integer_count_is_rejected
    raw = JSON.parse(receipt)
    raw["pagination"]["count"] = "12"
    assert_includes inspect_json(JSON.generate(raw)).errors, "invalid_pagination_metadata"
  end
end
