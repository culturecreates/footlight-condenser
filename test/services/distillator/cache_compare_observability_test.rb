require "test_helper"

class Distillator::CacheCompareObservabilityTest < ActiveSupport::TestCase
  setup do
    @url = "https://example.org/observability"
    @html = "<title>Same event</title><p>Same data</p>"
    @cache = Distillator::FetchCache.create!(uri_key: CGI.escape(@url), normalized_url: @url, html: @html, body: @html,
      headers: {}, http_response_code: 200, final_url: @url, scrape_date: Time.current, successful_refresh: Time.current,
      signals: { transport_success: true, content_success: true, content_type: "html", network_status: "ok" })
  end

  test "operator and strict policies treat absent healthy legacy telemetry as additions" do
    %i[operator strict].each do |policy|
      result = compare({ html: @html }, policy: policy)
      assert result.dig(:summary, :promotable)
      assert_empty result.dig(:summary, :review_needed_diffs)
      assert_empty result.dig(:summary, :operational_failures)
      %i[http_code final_url content_type transport_success content_success].each do |field|
        assert_includes result.dig(:summary, :improvements), field
      end
      assert_match /Additional Condenser diagnostics/, result.dig(:summary, :primary_reason)
    end
  end

  test "shared failure observations remain unsafe even when there are no corresponding diffs" do
    @cache.update!(http_response_code: 503, signals: { transport_success: false, content_success: false, network_status: "failed" })
    result = compare({ html: @html, http_code: 503, final_url: @url,
      signals: { "transport_success" => false, "content_success" => false, "network_status" => "failed" } })
    assert_equal false, result.dig(:legacy_cache, :transport_success)
    assert result.dig(:diffs, :transport_success, :same)
    assert_includes result.dig(:summary, :operational_failures), :transport_success
    assert_includes result.dig(:summary, :operational_failures), :http_code
    assert_equal "blocked", result.dig(:summary, :outcome)
    assert_not result.dig(:summary, :promotable)
  end

  test "newly detected content failure or blocking issue cannot become additional healthy diagnostics" do
    @cache.update!(signals: { transport_success: true, content_success: false, content_type: "html", blocking_issue_key: "system_captcha" })
    result = compare({ html: @html })
    assert_includes result.dig(:summary, :operational_failures), :content_success
    assert_includes result.dig(:summary, :operational_failures), :blocking_issue
    assert_equal :distillator_improvement, result.dig(:diffs, :content_type, :classification)
    assert_equal :distillator_improvement, result.dig(:diffs, :content_success, :classification)
    assert_not_includes result.dig(:summary, :blocking_regressions), :content_success
    assert_not result.dig(:summary, :promotable)
  end

  test "nonblocking issue observations are not regressions" do
    @cache.update!(signals: @cache.signals.merge("primary_issue_key" => "extra_monitoring_note"))
    result = compare({ html: @html })
    assert_empty result.dig(:summary, :operational_failures)
    assert_empty result.dig(:summary, :blocking_regressions)
    assert result.dig(:summary, :promotable)
  end

  test "older successful rendered cache rows keep the observation and report raw hash drift" do
    @cache.update!(signals: @cache.signals.merge(
      "primary_issue_key" => "legacy_phantomjs", "blocking_issue_key" => "legacy_phantomjs",
      "primary_issue_severity" => "info", "policy_action" => "observe", "issue_keys" => ["legacy_phantomjs"]
    ), hints: ["legacy_phantomjs"])
    legacy_html = "#{@html}<!-- render version=1 -->"
    rendered_html = "#{@html}<!-- render version=2 -->"
    @cache.update!(html: rendered_html, body: rendered_html)

    %i[operator strict].each do |policy|
      result = compare({ html: legacy_html, http_code: 200, final_url: @url }, policy: policy)
      assert result.dig(:summary, :promotable)
      assert_equal "ready_with_metadata_notes", result.dig(:summary, :outcome)
      assert_empty result.dig(:summary, :operational_failures)
      assert_nil result.dig(:condenser_cache, :blocking_issue)
      assert_equal "legacy_phantomjs", result.dig(:condenser_cache, :signals, "primary_issue_key")
      assert_equal ["legacy_phantomjs"], result.dig(:condenser_cache, :hints)
      assert_equal :metadata_only, result.dig(:diffs, :html_sha256, :classification)
      assert_equal Digest::SHA256.hexdigest(rendered_html), result.dig(:diffs, :html_sha256, :distillator)
      assert_equal Digest::SHA256.hexdigest(legacy_html), result.dig(:diffs, :html_sha256, :legacy)
      assert result.dig(:diffs, :html_bytes, :same)
    end

    assert_equal "legacy_phantomjs", @cache.reload.signals["blocking_issue_key"]
  end

  test "older rendered cache rows cannot hide an independent blocking issue" do
    @cache.update!(signals: @cache.signals.merge(
      "primary_issue_key" => "legacy_phantomjs", "blocking_issue_key" => "legacy_phantomjs",
      "primary_issue_severity" => "info", "policy_action" => "observe",
      "issue_keys" => %w[legacy_phantomjs queue_it]
    ))

    result = compare({ html: @html, http_code: 200, final_url: @url })

    assert_equal "queue_it", result.dig(:condenser_cache, :blocking_issue)
    assert_includes result.dig(:summary, :operational_failures), :blocking_issue
    assert_equal "blocked", result.dig(:summary, :outcome)
    assert_not result.dig(:summary, :promotable)
  end

  test "known destination and content changes still need attention" do
    @cache.update!(final_url: "https://example.org/another-event")
    result = compare({ html: @html, final_url: @url })
    assert_includes result.dig(:summary, :review_needed_diffs), :final_url
    assert_not result.dig(:summary, :promotable)
    @cache.update!(html: "<title>Another event</title>")
    result = compare({ html: @html, final_url: @url })
    assert_includes result.dig(:summary, :blocking_regressions), :title
  end

  test "missing legacy html does not become a passing comparison" do
    result = compare({ title: "Same event", http_code: 200 })
    assert_not result.dig(:summary, :promotable)
    assert_includes result.dig(:summary, :unknown_diffs), :html_sha256
  end

  test "unknown telemetry on both sides is not a contradictory observation" do
    @cache.update!(signals: @cache.signals.merge("content_type" => "unknown"))
    result = compare({ html: @html })
    assert_equal :metadata_only, result.dig(:diffs, :content_type, :classification)
    assert_not_includes result.dig(:summary, :blocking_regressions), :content_type
  end

  private

  def compare(legacy, policy: :operator)
    Distillator::CacheCompare.call(uri: @url, legacy_lookup: ->(_) { legacy }, comparison_policy: policy)
  end
end
