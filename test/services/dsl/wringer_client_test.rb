require "test_helper"

class Dsl::WringerClientTest < ActiveSupport::TestCase
  test "successful fetch returns status ok, body string, wringer nil" do
    captured = {}
    agent = mock("agent")
    agent.expects(:get_file).with("wringer://resolved").returns("<html>ok</html>")

    use_wringer = lambda do |url, render_js, scrape_options|
      captured = { url: url, render_js: render_js, scrape_options: scrape_options }
      "wringer://resolved"
    end
    safe_wringer_call = ->(&blk) { blk.call }

    client = Dsl::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: { force_scrape_every_hrs: 2 },
      use_wringer: use_wringer,
      safe_wringer_call: safe_wringer_call,
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal :ok, result[:status]
    assert_equal "<html>ok</html>", result[:body]
    assert_nil result[:wringer]
    assert_equal(
      { url: "https://example.com/events", render_js: false, scrape_options: { force_scrape_every_hrs: 2 } },
      captured
    )
  end

  test "abort payload returns status abort with original payload preserved" do
    payload = ["abort_update", { error_type: "system_cloudflare", retry: true, cache: false }]
    safe_wringer_call = ->(&_) { payload }

    client = Dsl::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: safe_wringer_call,
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal :abort, result[:status]
    assert_equal payload, result[:body]
    assert_equal({ error_type: "system_cloudflare", retry: true, cache: false }, result[:wringer])
  end

  test "wringer status extracts retry and cache from top-level payload" do
    payload = [
      "abort_update",
      {
        error_type: "system_cloudflare",
        retry: false,
        cache: true,
        policy: { retry: true, cache: false }
      }
    ]

    client = Dsl::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { payload },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal({ error_type: "system_cloudflare", retry: false, cache: true }, result[:wringer])
  end

  test "wringer status falls back to retry and cache from nested policy" do
    payload = [
      "abort_update",
      {
        error_type: "system_queue",
        policy: { retry: true, cache: false }
      }
    ]

    client = Dsl::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { payload },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal({ error_type: "system_queue", retry: true, cache: false }, result[:wringer])
  end

  test "partial abort payload includes only available wringer status fields" do
    payload = ["abort_update", { error_type: "system_cloudflare" }]

    client = Dsl::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { payload },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal({ error_type: "system_cloudflare" }, result[:wringer])
  end

  test "render_js option is passed through to use_wringer" do
    captured = {}
    agent = mock("agent")
    agent.expects(:get_file).with("wringer://resolved").returns("<html>ok</html>")

    use_wringer = lambda do |url, render_js, scrape_options|
      captured = { url: url, render_js: render_js, scrape_options: scrape_options }
      "wringer://resolved"
    end

    client = Dsl::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: {},
      use_wringer: use_wringer,
      safe_wringer_call: ->(&blk) { blk.call },
      logger: Rails.logger
    )

    client.fetch(url: "https://example.com/events", render_js: true)

    assert_equal true, captured[:render_js]
  end

  test "custom scrape_options are passed through to use_wringer" do
    captured = {}
    agent = mock("agent")
    agent.expects(:get_file).with("wringer://resolved").returns("<html>ok</html>")

    use_wringer = lambda do |url, render_js, scrape_options|
      captured = { url: url, render_js: render_js, scrape_options: scrape_options }
      "wringer://resolved"
    end

    client = Dsl::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: {},
      use_wringer: use_wringer,
      safe_wringer_call: ->(&blk) { blk.call },
      logger: Rails.logger
    )

    options = { json_post: true, force_scrape_every_hrs: 1 }
    client.fetch(url: "https://example.com/events", scrape_options: options)

    assert_equal options, captured[:scrape_options]
  end

  test "nil and malformed abort payloads do not crash and have nil wringer status" do
    client = Dsl::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { nil },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")
    assert_equal :ok, result[:status]
    assert_nil result[:body]
    assert_nil result[:wringer]

    malformed_payload = ["abort_update", "broken-payload"]
    malformed_client = Dsl::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { malformed_payload },
      logger: Rails.logger
    )

    malformed = malformed_client.fetch(url: "https://example.com/events")
    assert_equal :ok, malformed[:status]
    assert_equal malformed_payload, malformed[:body]
    assert_nil malformed[:wringer]
  end
end
