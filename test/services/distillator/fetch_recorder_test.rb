require "test_helper"
require "digest/sha1"

class Distillator::FetchRecorderTest < ActiveSupport::TestCase
  setup do
    @url = "https://example.com/events"
    @site = "migration_test"
    @digest = Digest::SHA1.hexdigest(@url)
    @dir = Rails.root.join("data", "migration_fixtures", @site, "fetch")
    @path = @dir.join("#{@digest}.json")
    FileUtils.rm_f(@path)
    ENV["RECORD_FETCH"] = nil
    ENV["FETCH_SITE"] = nil
  end

  teardown do
    FileUtils.rm_f(@path)
    ENV["RECORD_FETCH"] = nil
    ENV["FETCH_SITE"] = nil
  end

  test "does nothing when disabled" do
    Distillator::FetchRecorder.record(
      url: @url,
      response: { status: :ok, body: "<html>ok</html>", final_url: nil, headers: {}, wringer: {} }
    )

    assert_not File.exist?(@path)
  end

  test "records one json file when enabled" do
    ENV["RECORD_FETCH"] = "true"
    ENV["FETCH_SITE"] = @site
    response = { status: :ok, body: "<html>ok</html>", final_url: nil, headers: {}, wringer: { signals: {} } }

    Distillator::FetchRecorder.record(url: @url, response: response)

    assert File.exist?(@path)
    payload = JSON.parse(File.read(@path))
    assert_equal @url, payload["url"]
    assert payload["recorded_at"].present?
    assert_equal "ok", payload.dig("response", "status")
    assert_equal "<html>ok</html>", payload.dig("response", "body")
    assert_equal({}, payload.dig("response", "headers"))
  end

  test "does not overwrite existing fixture file" do
    ENV["RECORD_FETCH"] = "true"
    ENV["FETCH_SITE"] = @site

    FileUtils.mkdir_p(@dir)
    File.write(@path, '{"sentinel":"keep"}')
    original = File.read(@path)

    Distillator::FetchRecorder.record(
      url: @url,
      response: { status: :ok, body: "<html>new</html>", final_url: "https://example.com/final", headers: {}, wringer: {} }
    )

    assert_equal original, File.read(@path)
  end
end
