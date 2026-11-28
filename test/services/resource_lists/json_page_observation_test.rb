# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/json_page_observation"

class JsonPageObservationTest < Minitest::Test
  def observe(body, status: 200, content_type: "application/json", **extra)
    ResourceLists::JsonPageObservation.call(http_status: status, content_type:, body:, **extra)
  end

  def test_nested_json_array_metadata_is_observed_without_event_assumptions
    result = observe('{"meta":{"total":35},"data":{"events":[{"id":"a","url":"/a"},{"id":"b"}]}}')
    assert result.json_observed?
    assert_equal %w[meta data], result.top_keys
    assert_equal [{ path: "$.data.events", length: 2, item_type: "object",
      first_item_keys: %w[id url] }], result.arrays
    assert_match(/\A[0-9a-f]{64}\z/, result.sha256)
  end

  def test_empty_event_array_is_observed_but_not_completion
    result = observe('{"events":[]}')
    assert result.json_observed?
    assert_equal 0, result.arrays.first[:length]
    refute result.respond_to?(:complete?)
  end

  def test_top_level_array_is_supported
    result = observe('[{"name":"A"}]')
    assert_equal "array", result.top_level
    assert_equal "$", result.arrays.first[:path]
  end

  def test_200_html_challenge_is_not_json
    assert_includes observe('<html>verify you are human</html>', content_type: "text/html").errors,
      "unexpected_content_type"
  end

  def test_http_errors_fail_closed
    assert_includes observe('{"events":[]}', status: 403).errors, "untrusted_http_status"
    assert_includes observe('{"events":[]}', status: 404).errors, "untrusted_http_status"
  end

  def test_malformed_json_fails_closed
    assert_includes observe('{"events":').errors, "invalid_json"
  end

  def test_json_scalar_is_not_a_calendar_envelope
    assert_includes observe('"ok"').errors, "unstructured_json"
  end

  def test_oversized_body_fails_before_parsing
    assert_includes observe('{"events":[]}', max_bytes: 5).errors, "oversized_body"
  end

  def test_plus_json_content_type_is_supported
    assert observe('{"items":[]}', content_type: "application/problem+json; charset=utf-8").json_observed?
  end

  def test_empty_body_or_bad_limit_is_inconclusive
    assert_includes observe("").errors, "missing_body"
    assert_includes observe("{}", max_bytes: 0).errors, "invalid_limit"
  end
end
