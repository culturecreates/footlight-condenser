require "test_helper"
require "digest/sha1"
require "json"

class Distillator::FetchReplayTest < ActiveSupport::TestCase
  setup do
    @url = "https://example.com/events"
    @site = "replay_test"
    @digest = Digest::SHA1.hexdigest(@url)
    @dir = Rails.root.join("data", "migration_fixtures", @site, "fetch")
    @path = @dir.join("#{@digest}.json")
    FileUtils.mkdir_p(@dir)
    FileUtils.rm_f(@path)
    ENV["REPLAY_FETCH"] = nil
    ENV["FETCH_SITE"] = nil
  end

  teardown do
    FileUtils.rm_f(@path)
    ENV["REPLAY_FETCH"] = nil
    ENV["FETCH_SITE"] = nil
  end

  def enable_replay!
    ENV["REPLAY_FETCH"] = "true"
    ENV["FETCH_SITE"] = @site
  end

  def write_fixture(url: @url, response: nil, include_url: true, include_response: true, raw: nil)
    if raw
      File.write(@path, raw)
      return
    end

    payload = { "recorded_at" => "2026-04-22T00:00:00Z" }
    payload["url"] = url if include_url
    payload["response"] = response if include_response
    File.write(@path, JSON.pretty_generate(payload))
  end

  def full_response(status: "ok", duration_ms: 12.3, headers: { "content_type" => "text/html" }, extra: {})
    {
      "status" => status,
      "body" => "<html>fixture</html>",
      "headers" => headers,
      "final_url" => "https://example.com/final",
      "redirect_chain" => ["https://example.com/start", "https://example.com/final"],
      "wringer" => { "signals" => { "network_status" => "ok" }, "hints" => ["redirected"] },
      "duration_ms" => duration_ms
    }.merge(extra)
  end

  test "replay returns expected response" do
    ENV["REPLAY_FETCH"] = "true"
    ENV["FETCH_SITE"] = @site
    expected = {
      status: :ok,
      body: "<html>ok</html>",
      headers: { content_type: "text/html" },
      final_url: "https://example.com/events",
      redirect_chain: ["https://example.com/events"],
      wringer: { signals: { network_status: "ok" }, hints: [] },
      duration_ms: 12.3
    }

    File.write(@path, <<~JSON)
      {
        "url": "#{@url}",
        "recorded_at": "2026-04-22T00:00:00Z",
        "response": {
          "status": "#{expected[:status]}",
          "body": "#{expected[:body]}",
          "headers": {"content_type": "text/html"},
          "final_url": "#{expected[:final_url]}",
          "redirect_chain": ["https://example.com/events"],
          "wringer": {"signals": {"network_status": "ok"}, "hints": []},
          "duration_ms": #{expected[:duration_ms]}
        }
      }
    JSON

    result = Distillator::FetchReplay.load(url: @url)

    assert_equal expected, result
  end

  test "missing file raises clear error" do
    ENV["REPLAY_FETCH"] = "true"
    ENV["FETCH_SITE"] = @site

    error = assert_raises(RuntimeError) { Distillator::FetchReplay.load(url: @url) }
    assert_equal "Missing replay fixture for URL: #{@url}", error.message
  end

  test "status is normalized to symbol" do
    enable_replay!
    write_fixture(response: full_response(status: "ok"))

    result = Distillator::FetchReplay.load(url: @url)

    assert_equal :ok, result[:status]
  end

  test "status abort is normalized to symbol" do
    enable_replay!
    write_fixture(response: full_response(status: "abort"))

    result = Distillator::FetchReplay.load(url: @url)

    assert_equal :abort, result[:status]
  end

  test "headers are normalized to symbol snake_case keys" do
    enable_replay!
    write_fixture(
      response: full_response(
        headers: {
          "Content-Type" => "text/html",
          "Cache-Control" => "max-age=0"
        }
      )
    )

    result = Distillator::FetchReplay.load(url: @url)

    assert_equal(
      {
        content_type: "text/html",
        cache_control: "max-age=0"
      },
      result[:headers]
    )
  end

  test "duration_ms is numeric and non-negative" do
    enable_replay!
    write_fixture(response: full_response(duration_ms: 9.5))

    result = Distillator::FetchReplay.load(url: @url)

    assert_kind_of Numeric, result[:duration_ms]
    assert_operator result[:duration_ms], :>=, 0
  end

  test "duration_ms defaults to zero when missing" do
    enable_replay!
    response = full_response
    response.delete("duration_ms")
    write_fixture(response: response)

    result = Distillator::FetchReplay.load(url: @url)

    assert_kind_of Numeric, result[:duration_ms]
    assert_equal 0, result[:duration_ms]
  end

  test "missing response key raises error" do
    enable_replay!
    write_fixture(include_response: false, include_url: true)

    error = assert_raises(RuntimeError) { Distillator::FetchReplay.load(url: @url) }
    assert_includes error.message, @path.to_s
    assert_includes error.message, @url
  end

  test "missing url key raises error" do
    enable_replay!
    write_fixture(include_url: false, include_response: true, response: full_response)

    error = assert_raises(RuntimeError) { Distillator::FetchReplay.load(url: @url) }
    assert_includes error.message, @path.to_s
    assert_includes error.message, @url
  end

  test "invalid JSON raises error" do
    enable_replay!
    write_fixture(raw: "{\"url\":\"#{@url}\",\"response\":")

    error = assert_raises(StandardError) { Distillator::FetchReplay.load(url: @url) }
    assert_includes error.message, @path.to_s
    assert_includes error.message, @url
  end

  test "replay response does not include unexpected keys" do
    enable_replay!
    write_fixture(response: full_response)

    result = Distillator::FetchReplay.load(url: @url)

    expected_keys = [
      :status,
      :body,
      :headers,
      :final_url,
      :redirect_chain,
      :wringer,
      :duration_ms
    ]

    assert_equal expected_keys.sort, result.keys.sort
  end

  test "fixture with extra field raises error" do
    enable_replay!
    write_fixture(response: full_response(extra: { "extra_field" => "boom" }))

    error = assert_raises(RuntimeError) { Distillator::FetchReplay.load(url: @url) }
    assert_match(/extra_field/, error.message)
    assert_includes error.message, @path.to_s
    assert_includes error.message, @url
  end

  test "replay matches recorded structure and defaults duration_ms to zero" do
    ENV["REPLAY_FETCH"] = "true"
    ENV["FETCH_SITE"] = @site
    expected = {
      status: :abort,
      body: ["abort_update", { error_type: "WringerFetchError" }],
      headers: { content_type: "text/html" },
      final_url: "https://example.com/final",
      redirect_chain: ["https://example.com/start", "https://example.com/final"],
      wringer: { signals: {}, hints: [] },
      duration_ms: 0
    }

    File.write(@path, <<~JSON)
      {
        "url": "#{@url}",
        "recorded_at": "2026-04-22T00:00:00Z",
        "response": {
          "status": "abort",
          "body": ["abort_update", {"error_type": "WringerFetchError"}],
          "headers": {"content_type": "text/html"},
          "final_url": "https://example.com/final",
          "redirect_chain": ["https://example.com/start", "https://example.com/final"],
          "wringer": {"signals": {}, "hints": []}
        }
      }
    JSON

    result = Distillator::FetchReplay.load(url: @url)

    assert_equal expected, result
  end

  test "replay preserves full fetch metadata" do
    ENV["REPLAY_FETCH"] = "true"
    ENV["FETCH_SITE"] = @site

    File.write(@path, <<~JSON)
      {
        "url": "#{@url}",
        "recorded_at": "2026-04-22T00:00:00Z",
        "response": {
          "status": "ok",
          "body": "<html>fixture</html>",
          "headers": {"content_type": "text/html", "cache_control": "max-age=0"},
          "final_url": "https://example.com/final",
          "redirect_chain": ["https://example.com/start", "https://example.com/final"],
          "wringer": {"signals": {"network_status": "ok"}, "hints": ["redirected"]},
          "duration_ms": 55.5
        }
      }
    JSON

    result = Distillator::FetchReplay.load(url: @url)

    assert result.key?(:final_url), "missing final_url in replay response"
    assert result.key?(:headers), "missing headers in replay response"
    assert result.key?(:status), "missing status in replay response"
    assert result.key?(:body), "missing body in replay response"
    assert result.key?(:redirect_chain), "missing redirect_chain in replay response"
    assert result.key?(:wringer), "missing wringer in replay response"
    assert result.key?(:duration_ms), "missing duration_ms in replay response"

    assert_equal :ok, result[:status]
    assert_equal "<html>fixture</html>", result[:body]
    assert_equal({ content_type: "text/html", cache_control: "max-age=0" }, result[:headers])
    assert_equal "https://example.com/final", result[:final_url]
    assert_equal ["https://example.com/start", "https://example.com/final"], result[:redirect_chain]
    assert_equal({ signals: { network_status: "ok" }, hints: ["redirected"] }, result[:wringer])
    assert_equal 55.5, result[:duration_ms]
  end

  test "fetch service uses replay when enabled" do
    ENV["REPLAY_FETCH"] = "true"
    Distillator::FetchReplay.expects(:load).with(url: @url).returns(
      status: :ok,
      body: "<html>fixture</html>",
      headers: { content_type: "text/html" },
      final_url: "https://example.com/final",
      redirect_chain: ["https://example.com/start", "https://example.com/final"],
      wringer: { signals: {}, hints: [] },
      duration_ms: 0
    )
    Distillator::FetchService.expects(:legacy_fetch).never
    Distillator::FetchService.expects(:internal_fetch).never

    result = Distillator::FetchService.fetch(url: @url)

    assert_equal :ok, result[:status]
    assert_equal "<html>fixture</html>", result[:body]
    assert_equal({ content_type: "text/html" }, result[:headers])
    assert_equal "https://example.com/final", result[:final_url]
    assert_equal ["https://example.com/start", "https://example.com/final"], result[:redirect_chain]
    assert_equal({ signals: {}, hints: [] }, result[:wringer])
    assert_equal 0, result[:duration_ms]
  end
end
