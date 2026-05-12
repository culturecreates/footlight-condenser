require "test_helper"
require "digest/sha1"

class Distillator::FetchResponseContractTest < ActiveSupport::TestCase
  CONTRACT_KEYS = [
    :status,
    :body,
    :headers,
    :final_url,
    :redirect_chain,
    :wringer,
    :duration_ms
  ].freeze

  setup do
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    @old_replay_fetch = ENV["REPLAY_FETCH"]
    @old_fetch_site = ENV["FETCH_SITE"]
    @url = "https://example.com/events"
    @replay_site = "fetch_response_contract_test"
    @replay_digest = Digest::SHA1.hexdigest(@url)
    @replay_dir = Rails.root.join("data", "migration_fixtures", @replay_site, "fetch")
    @replay_path = @replay_dir.join("#{@replay_digest}.json")
    FileUtils.mkdir_p(@replay_dir)
    FileUtils.rm_f(@replay_path)
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
    ENV["REPLAY_FETCH"] = @old_replay_fetch
    ENV["FETCH_SITE"] = @old_fetch_site
    FileUtils.rm_f(@replay_path)
  end

  test "legacy fetch returns canonical response contract" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchRecorder.stubs(:record)
    Distillator::FetchService.expects(:legacy_fetch).returns(
      status: :ok,
      body: "<html>legacy</html>",
      headers: { "Content-Type" => "text/html", "Cache-Control" => "max-age=0" },
      final_url: @url,
      redirect_chain: nil,
      wringer: { signals: {}, hints: [] }
    )

    response = Distillator::FetchService.fetch(url: @url)

    assert_contract(response)
    assert_equal(
      {
        content_type: "text/html",
        cache_control: "max-age=0"
      },
      response[:headers]
    )
    assert_equal [], response[:redirect_chain]
  end

  test "default fetch without website context returns canonical legacy response contract" do
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    Distillator::FetchRecorder.stubs(:record)
    Distillator::FetchService.expects(:legacy_fetch).returns(
      status: :ok,
      body: "<html>legacy-default</html>",
      headers: { "Content-Type" => "text/html" },
      final_url: @url,
      redirect_chain: nil,
      wringer: { signals: {}, hints: [] }
    )
    Distillator::FetchService.expects(:internal_fetch).never

    response = Distillator::FetchService.fetch(url: @url)

    assert_contract(response)
    assert_equal "<html>legacy-default</html>", response[:body]
    assert_equal [], response[:redirect_chain]
  end

  test "internal fetch returns canonical response contract" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchRecorder.stubs(:record)
    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    Distillator::FetchService.expects(:internal_fetch).returns(
      status: :ok,
      body: "<html>internal</html>",
      headers: { "Content-Type" => "text/html" },
      final_url: "https://example.com/final",
      redirect_chain: nil,
      wringer: { signals: { network_status: "ok" }, hints: [] }
    )
    Distillator::FetchService.expects(:legacy_fetch).never

    response = Distillator::FetchService.fetch(
      url: @url,
      mode: :internal,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call }
    )

    assert_contract(response)
    assert_equal({ content_type: "text/html" }, response[:headers])
    assert_equal [], response[:redirect_chain]
  end

  test "shadow fetch returns canonical response contract" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchRecorder.stubs(:record)
    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    Distillator::FetchService.expects(:legacy_fetch).returns(
      status: :ok,
      body: "<html>legacy</html>",
      headers: { "Content-Type" => "text/html" },
      final_url: @url,
      redirect_chain: nil,
      wringer: { signals: {}, hints: [] }
    )
    Distillator::FetchService.expects(:internal_fetch).returns(
      status: :ok,
      body: "<html>internal</html>",
      headers: { content_type: "text/html" },
      final_url: @url,
      redirect_chain: [],
      wringer: { signals: {}, hints: [] }
    )
    Distillator::FetchShadowComparator.expects(:compare)

    response = Distillator::FetchService.fetch(
      url: @url,
      mode: :shadow,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call }
    )

    assert_contract(response)
    assert_equal({ content_type: "text/html" }, response[:headers])
    assert_equal [], response[:redirect_chain]
  end

  test "replay fetch returns canonical response contract" do
    ENV["REPLAY_FETCH"] = "true"
    ENV["FETCH_SITE"] = @replay_site

    File.write(@replay_path, <<~JSON)
      {
        "url": "#{@url}",
        "recorded_at": "2026-04-28T00:00:00Z",
        "response": {
          "status": "ok",
          "body": "<html>replay</html>",
          "headers": {"Content-Type": "text/html"},
          "final_url": "https://example.com/final",
          "redirect_chain": ["https://example.com/start", "https://example.com/final"],
          "wringer": {
            "signals": {
              "network_status": "ok",
              "content_type": "html",
              "redirect_type": "normal",
              "redirected": true,
              "final_url": "https://example.com/final"
            },
            "hints": []
          },
          "duration_ms": 12.3
        }
      }
    JSON

    response = Distillator::FetchService.fetch(url: @url)

    assert_contract(response)
    assert_equal({ content_type: "text/html" }, response[:headers])
    assert_equal ["https://example.com/start", "https://example.com/final"], response[:redirect_chain]
    assert_equal "ok", response.dig(:wringer, :signals, :network_status)
    assert_equal "html", response.dig(:wringer, :signals, :content_type)
    assert_equal "normal", response.dig(:wringer, :signals, :redirect_type)
    assert_equal true, response.dig(:wringer, :signals, :redirected)
    assert_equal "https://example.com/final", response.dig(:wringer, :signals, :final_url)
  end

  test "blocked fetch returns canonical response contract" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchRecorder.stubs(:record)

    response = Distillator::FetchService.fetch(
      url: "http://127.0.0.1/events",
      mode: :internal,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call }
    )

    assert_contract(response)
    assert_equal :abort, response[:status]
    assert_equal({}, response[:headers])
    assert_equal [], response[:redirect_chain]
    assert_equal "blocked_url", response.dig(:wringer, :signals, :native_ineligible_reason)
    assert_equal "blocked_private_ip", response.dig(:wringer, :signals, :guard_reason)
  end

  test "abort control result returns canonical response contract" do
    ENV["DISTILLATOR_FETCH_MODE"] = nil
    Distillator::FetchRecorder.stubs(:record)
    payload = ["abort_update", { error_type: "wringer_unreachable", retry: true, cache: false }]
    client = mock("wringer_client")
    client.expects(:fetch).with(url: @url).returns(
      status: :abort,
      body: payload,
      wringer: {
        error_type: "WringerFetchError",
        retry: true,
        cache: false,
        signals: {},
        hints: []
      }
    )

    response = Distillator::FetchService.fetch(url: @url, client: client)

    assert_contract(response)
    assert_equal :abort, response[:status]
    assert_equal({}, response[:headers])
    assert_equal [], response[:redirect_chain]
    assert_equal "WringerFetchError", response.dig(:wringer, :error_type)
  end

  test "failed network result returns canonical response contract" do
    ENV["DISTILLATOR_FETCH_MODE"] = nil
    Distillator::FetchRecorder.stubs(:record)
    failed_payload = ["abort_update", { error_type: "WringerFetchError" }]
    client = mock("wringer_client")
    client.expects(:fetch).with(url: @url).returns(
      status: :abort,
      body: failed_payload,
      wringer: {
        error_type: "WringerFetchError",
        retry: true,
        cache: false,
        signals: { network_status: "failed" },
        hints: ["timeout"]
      }
    )

    response = Distillator::FetchService.fetch(url: @url, client: client)

    assert_contract(response)
    assert_equal :abort, response[:status]
    assert_equal({}, response[:headers])
    assert_equal [], response[:redirect_chain]
    assert_equal "failed", response.dig(:wringer, :signals, :network_status)
  end

  private

  def assert_contract(response)
    assert_equal CONTRACT_KEYS.sort, response.keys.sort
    assert_kind_of Hash, response[:headers]
    assert_kind_of Array, response[:redirect_chain]
    assert_kind_of Numeric, response[:duration_ms]
  end

  def fetch_guard_allowed
    Distillator::FetchGuard::Result.new(allowed: true)
  end
end
