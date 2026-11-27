# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require_relative "../../../app/services/resource_lists/rendered_terminal_evidence"

class RenderedTerminalEvidenceTest < Minitest::Test
  EMPTY_TEXT = "Il n'y a aucun événement"

  def fixtures
    captures = (1..3).map do |number|
      { "page" => number, "requested_url" => "https://example.org/fr/calendrier?page=#{number}&number_items=48&typeevenement%5B%5D=musique&typeevenement%5B%5D=theatre",
        "sha256" => Digest::SHA256.hexdigest("page#{number}"), "rendered_at" => "2026-11-27T20:00:0#{number}Z",
        "fetch_path" => "native", "challenge_hint" => false, "ajax_shell_only" => false }
    end
    cards = lambda do |count|
      Array.new(count) { |i| { tag: "article", raw_hrefs: ["/event/#{i % 47}"] } }
    end
    pages = captures.map.with_index do |receipt, index|
      is_tail = index == 2
      entries = is_tail ? [{ tag: "p", raw_hrefs: [], text: EMPTY_TEXT }] : cards.call(index == 0 ? 48 : 44)
      { page: receipt["page"], requested_url: receipt["requested_url"], html_sha256: receipt["sha256"],
        reported_items_found: "92", container_found: true, direct_elements: entries.length,
        cards: entries, terminal_message: is_tail ? EMPTY_TEXT : nil }
    end
    manifest = { "purpose" => "read_only_rendered_resource_list_diagnostic", "verified_completeness" => false,
      "page_parameter" => "page", "pages_fetched" => 3, "max_pages" => 3,
      "stop_reason" => "heuristic_short_page", "captures" => captures }
    audit = { purpose: "offline_rendered_calendar_card_audit", verified_completeness: false, pages: pages }
    [manifest, audit]
  end

  def check(manifest, audit, text: EMPTY_TEXT)
    ResourceLists::RenderedTerminalEvidence.call(manifest: manifest, audit: audit, exact_empty_text: text)
  end

  def test_candidate_uses_card_occurrences_not_unique_event_urls
    manifest, audit = fixtures
    result = check(manifest, audit)
    assert result.terminal_candidate?
    assert_equal 92, result.observed_cards
    assert_equal 92, result.reported_total
    assert_equal 3, result.terminal_page
    assert_empty result.errors
    refute result.respond_to?(:complete?)
    refute_nil result.digest
  end

  def test_rejects_missing_middle_page
    manifest, audit = fixtures
    manifest["captures"][1]["page"] = 4
    assert_includes check(manifest, audit).errors, "broken_or_unfiltered_page_chain:1"
  end

  def test_rejects_lost_category_filter_even_when_page_number_is_right
    manifest, audit = fixtures
    manifest["captures"][1]["requested_url"] = manifest["captures"][1]["requested_url"].sub("&typeevenement%5B%5D=theatre", "")
    audit[:pages][1][:requested_url] = manifest["captures"][1]["requested_url"]
    assert_includes check(manifest, audit).errors, "broken_or_unfiltered_page_chain:1"
  end

  def test_rejects_mismatching_saved_html
    manifest, audit = fixtures
    audit[:pages][1][:html_sha256] = "bad-digest"
    assert_includes check(manifest, audit).errors, "snapshot_digest_mismatch:1"
  end

  def test_rejects_unrendered_or_challenge_page
    manifest, audit = fixtures
    manifest["captures"][2]["ajax_shell_only"] = true
    manifest["captures"][1]["challenge_hint"] = true
    assert_includes check(manifest, audit).errors, "untrusted_rendered_fetch:2"
    assert_includes check(manifest, audit).errors, "untrusted_rendered_fetch:1"
  end

  def test_rejects_wrong_or_missing_explicit_empty_message
    manifest, audit = fixtures
    audit[:pages].last[:terminal_message] = "Aucun résultat"
    assert_includes check(manifest, audit).errors, "missing_exact_empty_terminal:2"
    assert_equal ["missing_explicit_empty_text"], check(manifest, audit, text: "").errors
  end

  def test_rejects_card_count_shortfall_not_url_duplicates
    manifest, audit = fixtures
    audit[:pages][1][:cards].pop
    audit[:pages][1][:direct_elements] -= 1
    assert_includes check(manifest, audit).errors, "reported_total_does_not_match_cards"
  end

  def test_rejects_linkless_nonterminal_card
    manifest, audit = fixtures
    audit[:pages][1][:cards].first[:raw_hrefs] = []
    assert_includes check(manifest, audit).errors, "incomplete_nonterminal_cards:1"
  end

  def test_rejects_inconsistent_total_or_missing_container
    manifest, audit = fixtures
    audit[:pages][1][:reported_items_found] = "91"
    audit[:pages][0][:container_found] = false
    result = check(manifest, audit)
    assert_includes result.errors, "inconsistent_reported_totals"
    assert_includes result.errors, "missing_or_inconsistent_container:0"
  end

  def test_rejects_excessive_time_skew_and_untrusted_stop
    manifest, audit = fixtures
    manifest["captures"][2]["rendered_at"] = "2026-11-27T21:00:00Z"
    assert_includes check(manifest, audit).errors, "capture_freshness_skew"
    manifest["stop_reason"] = "max_pages_reached"
    assert_equal ["probe_stopped_without_terminal_observation"], check(manifest, audit).errors
  end
end
