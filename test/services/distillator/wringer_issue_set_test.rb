require "test_helper"

class Distillator::WringerIssueSetTest < ActiveSupport::TestCase
  test "select_primary prefers higher severity issue over yaml order" do
    matches = [
      {
        key: "empty_body",
        rule: { "category" => "content", "severity" => "warning" }
      },
      {
        key: "http_5xx",
        rule: { "category" => "http", "severity" => "failed" }
      }
    ]

    assert_equal "http_5xx", Distillator::WringerIssueSet.select_primary(matches)[:key]
  end

  test "call returns severity-aware primary issue" do
    issue_set = Distillator::WringerIssueSet.call(
      body: "",
      http_code: 500,
      final_url: "https://example.org/failure",
      hints: ["empty_body"],
      signals: {}
    )

    assert_equal "http_5xx", issue_set.primary[:key]
    assert_equal "http_server_error", issue_set.primary[:error_type]
  end

  test "phantomjs unavailable is primary when no stronger issue exists" do
    issue_set = Distillator::WringerIssueSet.call(
      body: nil,
      http_code: nil,
      final_url: "https://example.org/rendered",
      hints: ["legacy_phantomjs", "phantomjs_unavailable"],
      signals: { renderer_unavailable: true, renderer: "legacy_phantomjs" }
    )

    assert_includes issue_set.matches.map { |match| match[:key] }, "legacy_phantomjs"
    assert_includes issue_set.matches.map { |match| match[:key] }, "phantomjs_unavailable"
    assert_equal "phantomjs_unavailable", issue_set.primary[:key]
    assert_equal "abort_update", issue_set.primary[:action]
    assert_equal false, issue_set.primary[:cache]
    assert_equal true, issue_set.primary[:retry]
  end
end
