require "test_helper"
require "open3"
require_relative "../../script/distillator_shadow_log_summary"

class DistillatorShadowLogSummaryTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join("test", "fixtures", "files", "distillator_shadow_logs", "sample.log")

  test "summarizes shadow observation log metrics" do
    summary = DistillatorShadowLogSummary.call(FIXTURE)

    assert_equal 5, summary[:total_comparisons]
    assert_equal 2, summary[:matched_count]
    assert_equal 3, summary[:mismatch_count]
    assert_equal 1, summary[:shadow_errors_count]
    assert_equal 1, summary[:internal_ineligible_count]
    assert_equal 1, summary[:blocked_fetch_count]
    assert_equal 2, summary[:mismatch_fields]["body_hash"]
    assert_equal 2, summary[:mismatch_fields]["final_url"]
    assert_equal 1, summary[:mismatch_fields]["wringer_error_type"]
  end

  test "prints concise report without full body content" do
    report = DistillatorShadowLogSummary.new(FIXTURE).report

    assert_includes report, "Total comparisons: 5"
    assert_includes report, "Matched: 2"
    assert_includes report, "Mismatched: 3"
    assert_includes report, "body_hash: 2"
    assert_includes report, "final_url: 2"
    refute_includes report, "<html"
  end

  test "command line output succeeds for local log file" do
    stdout, stderr, status = Open3.capture3(
      "ruby",
      Rails.root.join("script", "distillator_shadow_log_summary.rb").to_s,
      FIXTURE.to_s
    )

    assert status.success?, stderr
    assert_includes stdout, "Distillator shadow log summary"
    assert_includes stdout, "Blocked fetches: 1"
  end
end
