require "test_helper"
require "webmock/minitest"

class DslContractTest < ActiveSupport::TestCase
  include DslRunnerTestHelper

  test "if_xpath halts when no match" do
    expect_no_fetch_seams
    runner, = build_runner_with_html(html: "<html></html>")

    result = runner.run("if_xpath=//title; xpath=//h1")

    assert_empty result
    assert_no_wringer_requests
  end

  test "if_xpath continues when match exists" do
    expect_no_fetch_seams
    runner, = build_runner_with_html(html: "<html><title>T</title><h1>H</h1></html>")

    result = runner.run("if_xpath=//title; xpath=//h1")

    assert_equal ["H"], result
    assert_no_wringer_requests
  end

  test "unless_xpath halts when match exists" do
    expect_no_fetch_seams
    runner, = build_runner_with_html(html: "<html><title>T</title><h1>H</h1></html>")

    result = runner.run("unless_xpath=//title; xpath=//h1")

    assert_empty result
    assert_no_wringer_requests
  end

  test "unless_xpath continues when no match" do
    expect_no_fetch_seams
    runner, = build_runner_with_html(html: "<html><h1>H</h1></html>")

    result = runner.run("unless_xpath=//title; xpath=//h1")

    assert_equal ["H"], result
    assert_no_wringer_requests
  end

  test "xpath replaces previous results" do
    expect_no_fetch_seams
    runner, = build_runner_with_html(html: "<html><p>A</p><h1>H</h1></html>")

    result = runner.run("xpath=//p/text(); xpath=//h1/text()")

    assert_equal ["H"], result
    assert_no_wringer_requests
  end

  test "ruby replaces previous results" do
    expect_no_fetch_seams
    runner, = build_runner_with_html(html: "<html><p>a</p><p>b</p></html>")

    result = runner.run("xpath=//p/text(); ruby=$array.map(&:upcase)")

    assert_equal %w[A B], result
    assert_no_wringer_requests
  end

  test "json replaces previous results" do
    expect_no_fetch_seams
    runner, = build_runner_with_text(text: '{"name":"test"}')

    result = runner.run("json=$json['name']")

    assert_equal "test", result
    assert_no_wringer_requests
  end

  test "url step does not change results" do
    client = mock("wringer_client")
    client.expects(:fetch).with(
      url: "http://example.com",
      render_js: false,
      scrape_options: { wringer_compatibility: true }
    ).returns(
      status: :ok,
      body: "<html></html>",
      headers: {},
      final_url: "http://example.com",
      redirect_chain: [],
      wringer: { signals: {}, hints: [] },
      duration_ms: 0
    )
    Dsl::Support::WringerClient.expects(:new).returns(client)
    Distillator::FetchCacheStore.expects(:fetch).never

    runner, = build_compat_runner(url: "http://example.com", tracer: Dsl::Tracing::NullTracer.new)

    result = runner.run("url='http://example.com'; xpath=//h1")

    assert_empty result
    assert_no_wringer_requests
  end

  test "manual returns constant value" do
    expect_no_fetch_seams
    runner, = build_runner_with_html

    result = runner.run("manual=Hello")

    assert_equal ["Hello"], result
    assert_no_wringer_requests
  end

  test "invalid ruby returns abort_update" do
    expect_no_fetch_seams
    runner, = build_runner_with_html

    result = runner.run("ruby=invalid ruby(")

    assert_equal "abort_update", result.first
    assert result.last[:error]
    assert_no_wringer_requests
  end

  test "no step accumulates results implicitly" do
    expect_no_fetch_seams
    runner, = build_runner_with_html(html: "<html><p>a</p><h1>b</h1></html>")

    result = runner.run("xpath=//p/text(); xpath=//h1/text()")

    assert_not_includes result, "a"
    assert_equal ["b"], result
    assert_no_wringer_requests
  end

  test "real world ticket extraction pipeline preserves semantics" do
    skip "Known issue sentinel: extraction drift (kept for regression visibility)"
  end
end
