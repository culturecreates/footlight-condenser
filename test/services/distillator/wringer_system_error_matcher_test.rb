require "test_helper"

class Distillator::WringerSystemErrorMatcherTest < ActiveSupport::TestCase
  test "matches high specificity and generic yaml rules in order" do
    assert_equal "system_cloudflare", match_for(body: "Attention Required by Cloudflare", http_code: 200)[:error_type]
    assert_equal "system_queue", match_for(body: "Queue-it Please wait while we redirect you", http_code: 200)[:error_type]
    assert_equal "system_akamai", match_for(body: "Access Denied Reference #123", http_code: 200)[:error_type]
    assert_equal "empty_body", match_for(body: "", http_code: 200)[:error_type]
    assert_equal "html_error_page", match_for(body: "Internal Server Error", http_code: 200)[:error_type]
    assert_equal "redirect_to_listing", match_for(body: "<html>ok</html>", http_code: 200, final_url: "https://example.org/events", signals: { redirect_type: "normal" })[:error_type]
    assert_equal "http_404", match_for(body: "Not Found", http_code: 404)[:error_type]
    assert_equal "http_server_error", match_for(body: "Server Error", http_code: 500)[:error_type]
  end

  test "body blank matches nil and empty string" do
    rules = [["empty_body", { "match" => { "body_blank" => true }, "policy" => { "error_code" => "empty_body", "retry" => false, "cache" => false, "delete" => false } }]]

    nil_match = Distillator::WringerSystemErrorMatcher.call(body: nil, http_code: 200, final_url: "https://example.org/item", rules: rules)
    empty_match = Distillator::WringerSystemErrorMatcher.call(body: "", http_code: 200, final_url: "https://example.org/item", rules: rules)

    assert_equal "empty_body", nil_match[:error_type]
    assert_equal false, nil_match[:retry]
    assert_equal false, nil_match[:cache]
    assert_equal false, nil_match[:delete]
    assert_equal "empty_body", empty_match[:error_type]
  end

  test "matches apify legacy additions" do
    assert_equal "system_reservatech_waiting_room", match_for(body: "Reservatech waiting room", http_code: 200)[:error_type]
    assert_equal "system_salle_attente", match_for(body: "Salle d'attente", http_code: 200)[:error_type]
    assert_equal "system_captcha", match_for(body: "captcha", http_code: 200)[:error_type]
    assert_equal "forbidden_text", match_for(body: "Forbidden", http_code: 200)[:error_type]
    assert_equal "generic_error_text", match_for(body: "<html><body><h1>Une erreur est survenue</h1></body></html>", http_code: 200)[:error_type]
    assert_equal "post_call_observed", match_for(body: "POST call", http_code: 200)[:error_type]
    assert_equal "http_403", match_for(body: "Nope", http_code: 403)[:error_type]
  end

  test "generic error text captures a matched snippet from body text" do
    issue = match_for(body: "<html><body><main><h1>Une erreur est survenue</h1><p>Veuillez reessayer.</p></main></body></html>", http_code: 200)

    assert_equal "generic_error_text", issue[:key]
    assert_equal "body_text", issue.dig(:match_details, :source)
    assert_equal "Une erreur est survenue", issue.dig(:match_details, :pattern)
    assert_match "Une erreur est survenue", issue.dig(:match_details, :snippet)
  end

  test "generic error text does not match ordinary page text with error words in markup" do
    issue = match_for(body: "<html><head><script>var lastError = null;</script></head><body><h1>Festival program</h1><p>Welcome.</p></body></html>", http_code: 200)

    assert_nil issue
  end

  test "matches by hint and signal" do
    assert_equal "blocked_url", match_for(body: ["abort_update"], http_code: nil, hints: ["blocked_url"], signals: { network_status: "blocked" })[:error_type]
    assert_equal "timeout", match_for(body: ["abort_update"], http_code: nil, hints: ["timeout"], signals: { network_status: "failed" })[:error_type]
    assert_equal "ssl_verify_none_fallback", match_for(body: "<html>ok</html>", http_code: 200, hints: ["ssl_verify_none_fallback"], signals: { ssl_verify_none_fallback: true })[:error_type]
    assert_equal "legacy_phantomjs", match_for(body: "<html>ok</html>", http_code: 200, hints: ["legacy_phantomjs"], signals: { fetch_backend: "phantomjs" })[:error_type]
    assert_equal "phantomjs_unavailable", match_for(body: nil, http_code: nil, hints: ["phantomjs_unavailable"], signals: { renderer_unavailable: true, renderer: "legacy_phantomjs" })[:error_type]
    assert_equal "json_post", match_for(body: '{"ok":true}', http_code: 200, signals: { request_method: "POST", content_type: "json" })[:error_type]
  end

  test "all matches can prefer failure over info for primary issue selection" do
    issue_set = Distillator::WringerIssueSet.call(
      body: nil,
      http_code: 500,
      final_url: "https://example.org/item",
      hints: ["legacy_phantomjs"],
      signals: { request_method: "POST", content_type: "json" }
    )

    assert_includes issue_set.matches.map { |match| match[:key] }, "json_post"
    assert_includes issue_set.matches.map { |match| match[:key] }, "http_5xx"
    assert_equal "http_5xx", issue_set.primary[:key]
  end

  test "call prefers failed http issue over warning empty body" do
    issue = Distillator::WringerSystemErrorMatcher.call(
      body: "",
      http_code: 500,
      final_url: "https://example.org/failure",
      hints: ["empty_body"],
      signals: {}
    )

    assert_equal "http_5xx", issue[:key]
    assert_equal "http_server_error", issue[:error_type]
  end

  test "call prefers redirect delete issue over empty body when redirect signals match" do
    issue = Distillator::WringerSystemErrorMatcher.call(
      body: "",
      http_code: 200,
      final_url: "https://example.org/events",
      hints: ["empty_body"],
      signals: { redirect_type: "normal" }
    )

    assert_equal "redirect_to_listing", issue[:key]
    assert_equal true, issue[:delete]
  end

  test "invalid regex remains non fatal" do
    result = Distillator::WringerSystemErrorMatcher.call(
      body: "ok",
      http_code: 200,
      final_url: "https://example.org/events",
      rules: [["bad_regex", { "match" => { "final_url_patterns" => ["*invalid["] }, "policy" => { "error_code" => "bad_regex" } }]]
    )

    assert_nil result
  end

  test "specific anti bot issue wins over redirect listing when both match" do
    issue_set = Distillator::WringerIssueSet.call(
      body: "<html>Queue-it Please wait while we redirect you</html>",
      http_code: 200,
      final_url: "https://example.com/events",
      signals: { redirect_type: "normal", network_status: "ok" }
    )

    assert_includes issue_set.matches.map { |m| m[:key] }, "queue_it"
    assert_includes issue_set.matches.map { |m| m[:key] }, "redirect_to_listing"
    assert_equal "queue_it", issue_set.primary[:key]
  end

  private

  def match_for(body:, http_code:, final_url: "https://example.org/item", hints: [], signals: {})
    Distillator::WringerSystemErrorMatcher.call(body: body, http_code: http_code, final_url: final_url, hints: hints, signals: signals)
  end
end
