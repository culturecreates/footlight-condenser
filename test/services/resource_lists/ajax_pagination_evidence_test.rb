# frozen_string_literal: true

require "minitest/autorun"
require "json"
require_relative "../../../app/services/resource_lists/ajax_pagination_evidence"

class AjaxPaginationEvidenceTest < Minitest::Test
  DATA = JSON.parse(File.read(File.expand_path("../../fixtures/resource_lists/chasse_galerie_ajax_observations.json", __dir__)))

  # Only response metadata and the separate 28-card Prestige inventory were
  # preserved from the live trial. These per-page HTML bodies are reconstructed
  # test inputs, NOT independently captured page-1/2/3/4 HTTP responses.
  def captures(kind)
    config = DATA.fetch(kind)
    urls = config.fetch("single_page_capture", {}).fetch("event_urls", [])
    offset = 0
    config.fetch("observed_pages").map do |observed|
      page = observed.fetch("page")
      selected = observed["event_urls"] || urls.slice(offset, observed.fetch("count"))
      offset += observed.fetch("count")
      html = selected.empty? ? "<p>#{DATA.fetch('empty_text')}</p>" : selected.map do |href|
        %(<a class="cards__item" href="#{href}"><span class="categ-top">#{config.fetch('category_label')}</span></a>)
      end.join("\n")
      payload = { "count" => selected.length, "current_page" => page, "max" => observed.fetch("max"),
                  "html" => html, "url" => "#{DATA.fetch('calendar_url')}?page={page_number}&number_items=#{config.fetch('page_size')}&categ=#{config.fetch('category_id')}" }
      { "request" => { "endpoint" => DATA.fetch("endpoint"), "method" => "POST", "encoding" => "multipart/form-data",
                       "fields" => { "reference_id" => DATA.fetch("reference_id"), "filters[categ]" => config.fetch("category_id"),
                                     "current_page" => page.to_s, "number_items_per_page" => config.fetch("page_size").to_s,
                                     "action" => "null" } },
        "response" => { "http_status" => 200, "content_type" => "application/json; charset=utf-8", "body" => JSON.generate(payload) },
        "captured_at" => "2026-11-27T23:00:0#{page}Z" }
    end
  end

  def check(kind, receipts = captures(kind), **overrides)
    config = DATA.fetch(kind)
    ResourceLists::AjaxPaginationEvidence.call(
      captures: receipts, endpoint: DATA.fetch("endpoint"), calendar_url: DATA.fetch("calendar_url"),
      category_id: config.fetch("category_id"), category_label: config.fetch("category_label"),
      exact_empty_text: DATA.fetch("empty_text"), expected_total: config.fetch("expected_total"),
      **overrides
    )
  end

  def change_payload(receipts, index)
    payload = JSON.parse(receipts[index].fetch("response").fetch("body"))
    yield payload
    receipts[index]["response"]["body"] = JSON.generate(payload)
  end

  def test_jeunesse_three_page_sequence_matches_observed_urls_and_empty_tail
    result = check("jeunesse")
    assert result.terminal_candidate?, result.errors.inspect
    assert_equal 2, result.card_occurrences
    assert_equal 2, result.unique_event_urls
    assert_equal 3, result.terminal_page
    refute result.respond_to?(:complete?)
    refute_nil result.digest
  end

  def test_prestige_ten_ten_eight_empty_matches_independent_28_card_inventory
    assert_equal 28, DATA.dig("prestige", "single_page_capture", "event_urls").length
    assert_equal 28, DATA.dig("prestige", "single_page_capture", "event_urls").uniq.length
    result = check("prestige")
    assert result.terminal_candidate?, result.errors.inspect
    assert_equal 28, result.card_occurrences
    assert_equal 28, result.unique_event_urls
    assert_equal 4, result.terminal_page
  end

  def test_rejects_missing_middle_page
    receipts = captures("jeunesse")
    receipts.delete_at(1)
    assert_includes check("jeunesse", receipts).errors, "invalid_or_changed_request:1"
  end

  def test_rejects_category_filter_changed_in_request
    receipts = captures("prestige")
    receipts[1]["request"]["fields"]["filters[categ]"] = "different"
    assert_includes check("prestige", receipts).errors, "invalid_or_changed_request:1"
  end

  def test_rejects_category_mismatch_in_returned_cards
    receipts = captures("jeunesse")
    change_payload(receipts, 1) { |p| p["html"] = p["html"].sub("Jeunesse", "Prestige") }
    assert_includes check("jeunesse", receipts).errors, "category_mismatch:1"
  end

  def test_rejects_count_mismatch_and_unexpected_page_size
    receipts = captures("prestige")
    change_payload(receipts, 1) { |p| p["count"] = 9 }
    assert_includes check("prestige", receipts).errors, "card_count_mismatch:1"
    receipts = captures("jeunesse")
    change_payload(receipts, 0) { |p| p["count"] = 2 }
    assert_includes check("jeunesse", receipts).errors, "invalid_page_metadata:0"
  end

  def test_rejects_missing_or_changed_terminal_message
    receipts = captures("jeunesse")
    change_payload(receipts, 2) { |p| p["html"] = "<p>Empty</p>" }
    assert_includes check("jeunesse", receipts).errors, "missing_exact_empty_terminal:2"
  end

  def test_rejects_broken_response_page_or_filter_url
    receipts = captures("jeunesse")
    change_payload(receipts, 1) { |p| p["current_page"] = 1 }
    assert_includes check("jeunesse", receipts).errors, "invalid_page_metadata:1"
    receipts = captures("jeunesse")
    change_payload(receipts, 1) { |p| p["url"] = p["url"].sub("&categ=", "&dropped=") }
    assert_includes check("jeunesse", receipts).errors, "lost_filter_or_bad_url_template:1"
  end

  def test_rejects_json_or_http_error_instead_of_empty_page
    receipts = captures("jeunesse")
    receipts[2]["response"]["body"] = "<html>Access denied</html>"
    assert_includes check("jeunesse", receipts).errors, "invalid_json:2"
    receipts = captures("jeunesse")
    receipts[2]["response"]["http_status"] = 500
    assert_includes check("jeunesse", receipts).errors, "untrusted_ajax_response:2"
  end

  def test_rejects_limit_or_time_skew
    assert_equal ["invalid_capture_count"], check("prestige", captures("prestige"), max_pages: 3).errors
    receipts = captures("jeunesse")
    receipts[2]["captured_at"] = "2026-11-28T01:00:00Z"
    assert_includes check("jeunesse", receipts).errors, "capture_freshness_skew"
  end

  def test_max_is_stable_opaque_metadata_not_a_page_count
    receipts = captures("prestige")
    change_payload(receipts, 2) { |p| p["max"] = 27 }
    assert check("prestige", receipts).terminal_candidate?
    change_payload(receipts, 2) { |p| p["max"] = 3 }
    assert_includes check("prestige", receipts).errors, "inconsistent_max_metadata"
  end

  def test_repeated_event_href_with_distinct_performance_is_not_a_card_loss
    receipts = captures("jeunesse"); original = JSON.parse(receipts[0]["response"]["body"])["html"]
    change_payload(receipts, 1) { |p| p["html"] = original.sub("</a>", "<span>Different performance</span></a>") }
    result = check("jeunesse", receipts)
    assert result.terminal_candidate?, result.errors.inspect
    assert_equal 2, result.card_occurrences
    assert_equal 1, result.unique_event_urls
  end

  def test_rejects_repeated_nonterminal_html
    receipts = captures("jeunesse")
    change_payload(receipts, 1) { |p| p["html"] = JSON.parse(receipts[0]["response"]["body"])["html"] }
    assert_includes check("jeunesse", receipts).errors, "repeated_nonterminal_html"
  end
end
