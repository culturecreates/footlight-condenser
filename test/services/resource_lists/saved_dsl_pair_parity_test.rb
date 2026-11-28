# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/saved_dsl_pair_parity"

class SavedDslPairParityTest < Minitest::Test
  URL_ROOT = "https://www.tourismeshawinigan.com/evenements/"

  def report(label, id, pages)
    data = pages.each_with_index.map do |values, i|
      { "page" => i + 1, "url" => "https://www.tourismeshawinigan.com/evenements/?page=#{i + 1}",
        "count" => values.length, "values" => values, "sha256" => Digest::SHA256.hexdigest(JSON.generate(values)) }
    end
    all = pages.flatten
    { "source_id" => id, "property_label" => label, "status" => "dsl_replayed_parity_unverified",
      "website_id" => 12, "website_seedurl" => "tourismeshawinigan-com", "terminal_page" => pages.size,
      "network_disabled" => true, "db_transaction_read_only" => true, "verified_completeness" => false,
      "extraction_parity_verified" => false, "total_values" => all.size,
      "duplicate_values" => all.length - all.uniq.length, "pages" => data }
  end

  def setup
    a = URL_ROOT + "alpha/"
    b = URL_ROOT + "bravo/"
    @u = report("Webpage URL List", 9102, [[a, b], [b]])
    @r = report("URI List", 9098, [["footlight:tourismeshawinigan-com_alpha", "footlight:tourismeshawinigan-com_bravo"],
      ["footlight:tourismeshawinigan-com_bravo"]])
  end

  def run_audit
    ResourceLists::SavedDslPairParity.call(url_report: @u, uri_report: @r)
  end

  def recalc(report, index)
    p = report.fetch("pages")[index]
    p["sha256"] = Digest::SHA256.hexdigest(JSON.generate(p["values"]))
    report["duplicate_values"] = report["total_values"] - report["pages"].flat_map { |x| x["values"] }.uniq.length
  end

  def test_valid_pair_and_cross_page_duplicate
    result = run_audit
    assert_equal "url_uri_pairing_verified_last_good_unverified", result.status
    assert_equal 3, result.total_values
    assert_equal 2, result.unique_urls
    assert_equal 1, result.duplicate_occurrences
    assert_equal 2, result.terminal_page
  end

  def test_same_count_but_wrong_uri_fails
    @r["pages"][0]["values"][0] = "footlight:tourismeshawinigan-com_wrong"
    recalc(@r, 0)
    assert_includes run_audit.errors, "uri_mismatch:1:0"
  end

  def test_same_count_but_swapped_uri_order_fails
    @r["pages"][0]["values"].reverse!
    recalc(@r, 0)
    assert_includes run_audit.errors, "uri_mismatch:1:0"
  end

  def test_replay_status_is_required
    @r["status"] = "inconclusive"
    assert_includes run_audit.errors, "mismatched_status"
  end

  def test_safety_flags_are_required
    @u["network_disabled"] = false
    assert_includes run_audit.errors, "no_safety_evidence"
  end

  def test_same_source_identity_required
    @r["website_id"] = 99
    assert_includes run_audit.errors, "mismatched_website_id"
  end

  def test_page_target_mismatch
    @r["pages"][1]["url"] = "https://wrong.example/"
    assert_includes run_audit.errors, "mismatched_page_identity:2"
  end

  def test_page_count_mismatch
    @r["pages"][1]["values"] << "footlight:tourismeshawinigan-com_extra"
    assert_includes run_audit.errors, "mismatched_values_count:2"
  end

  def test_page_digest_mismatch
    @u["pages"][0]["sha256"] = "old"
    assert_includes run_audit.errors, "value_digest_mismatch:1"
  end

  def test_query_leakage_in_url
    @u["pages"][0]["values"][0] += "?occurrence_date=2026-12-01"
    recalc(@u, 0)
    assert_includes run_audit.errors, "invalid_event_url:1:0"
  end

  def test_uri_collision
    @r["pages"][0]["values"][0] = @r["pages"][0]["values"][1]
    recalc(@r, 0)
    assert_includes run_audit.errors, "uri_collision:1:1"
  end

  def test_duplicate_within_page
    a = URL_ROOT + "alpha/"
    @u["pages"][0]["values"] = [a, a]
    @r["pages"][0]["values"] = ["footlight:tourismeshawinigan-com_alpha"] * 2
    recalc(@u, 0)
    recalc(@r, 0)
    assert_includes run_audit.errors, "duplicates_within_page:1"
  end

  def test_bad_terminal_summary
    @u["terminal_page"] = 7
    @r["terminal_page"] = 7
    assert_includes run_audit.errors, "unexpected_terminal_page"
  end

  def test_requires_properties
    @r["property_label"] = "Description"
    assert_includes run_audit.errors, "uri_source_wrong_label"
  end
end
