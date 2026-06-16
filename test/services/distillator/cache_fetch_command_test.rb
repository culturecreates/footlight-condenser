require "test_helper"

class Distillator::CacheFetchCommandTest < ActiveSupport::TestCase
  test "normal command maps to force scrape without phantom or post" do
    fetch_result = Struct.new(:cache).new(nil)
    fetcher = mock("fetcher")
    guard = stub(check_url: Distillator::FetchGuard::Result.new(allowed: true))
    fetcher.expects(:fetch).with do |kwargs|
      assert_equal "https://example.org/events", kwargs[:uri]
      assert_equal true, kwargs[:force_scrape]
      assert_equal false, kwargs[:use_phantomjs]
      assert_equal false, kwargs[:json_post]
      assert_equal false, kwargs[:include_fragment]
      true
    end.returns(fetch_result)

    result = Distillator::CacheFetchCommand.new(
      params: { uri: "https://example.org/events", fetch_kind: "normal" },
      fetcher: fetcher,
      guard: guard
    ).call

    assert_equal true, result.ok?
    assert_equal [], result.errors
    assert_equal fetch_result, result.fetch_result
  end

  test "missing fetch kind defaults to normal" do
    fetcher = mock("fetcher")
    guard = stub(check_url: Distillator::FetchGuard::Result.new(allowed: true))
    fetcher.expects(:fetch).with do |kwargs|
      assert_equal false, kwargs[:use_phantomjs]
      assert_equal false, kwargs[:json_post]
      true
    end.returns(Struct.new(:cache).new(nil))

    result = Distillator::CacheFetchCommand.new(
      params: { uri: "https://example.org/default" },
      fetcher: fetcher,
      guard: guard
    ).call

    assert_equal true, result.ok?
  end

  test "blank fetch kind defaults to normal" do
    fetcher = mock("fetcher")
    guard = stub(check_url: Distillator::FetchGuard::Result.new(allowed: true))
    fetcher.expects(:fetch).with do |kwargs|
      assert_equal false, kwargs[:use_phantomjs]
      assert_equal false, kwargs[:json_post]
      true
    end.returns(Struct.new(:cache).new(nil))

    result = Distillator::CacheFetchCommand.new(
      params: { uri: "https://example.org/default", fetch_kind: "" },
      fetcher: fetcher,
      guard: guard
    ).call

    assert_equal true, result.ok?
  end

  test "rendered command maps to phantom and include fragment" do
    fetcher = mock("fetcher")
    guard = stub(check_url: Distillator::FetchGuard::Result.new(allowed: true))
    fetcher.expects(:fetch).with do |kwargs|
      assert_equal true, kwargs[:force_scrape]
      assert_equal true, kwargs[:use_phantomjs]
      assert_equal true, kwargs[:include_fragment]
      assert_equal false, kwargs[:json_post]
      true
    end.returns(Struct.new(:cache).new(nil))

    result = Distillator::CacheFetchCommand.new(
      params: { uri: "https://example.org/rendered", fetch_kind: "rendered", include_fragment: "false" },
      fetcher: fetcher,
      guard: guard
    ).call

    assert_equal true, result.ok?
  end

  test "post command maps to json post" do
    fetcher = mock("fetcher")
    guard = stub(check_url: Distillator::FetchGuard::Result.new(allowed: true))
    fetcher.expects(:fetch).with do |kwargs|
      assert_equal true, kwargs[:force_scrape]
      assert_equal false, kwargs[:use_phantomjs]
      assert_equal true, kwargs[:json_post]
      true
    end.returns(Struct.new(:cache).new(nil))

    result = Distillator::CacheFetchCommand.new(
      params: { uri: "https://example.org/post", fetch_kind: "post" },
      fetcher: fetcher,
      guard: guard
    ).call

    assert_equal true, result.ok?
  end

  test "invalid explicit fetch kind still fails" do
    fetcher = mock("fetcher")
    fetcher.expects(:fetch).never

    result = Distillator::CacheFetchCommand.new(
      params: { uri: "https://example.org/events", fetch_kind: "bogus" },
      fetcher: fetcher
    ).call

    assert_equal false, result.ok?
    assert_includes result.errors, "Fetch kind is invalid"
  end

  test "blank uri returns validation error and does not fetch" do
    fetcher = mock("fetcher")
    fetcher.expects(:fetch).never

    result = Distillator::CacheFetchCommand.new(
      params: { uri: "", fetch_kind: "normal" },
      fetcher: fetcher
    ).call

    assert_equal false, result.ok?
    assert_includes result.errors, "URI is invalid"
  end

  test "invalid uri returns validation error and does not fetch" do
    fetcher = mock("fetcher")
    fetcher.expects(:fetch).never

    result = Distillator::CacheFetchCommand.new(
      params: { uri: "http://[invalid", fetch_kind: "normal" },
      fetcher: fetcher
    ).call

    assert_equal false, result.ok?
    assert_includes result.errors, "URI is invalid"
  end

  test "optional fields preserve explicit user intent" do
    fetcher = mock("fetcher")
    guard = stub(check_url: Distillator::FetchGuard::Result.new(allowed: true))
    fetcher.expects(:fetch).with do |kwargs|
      assert_equal true, kwargs[:absolute_src]
      assert_equal true, kwargs[:include_fragment]
      assert_equal "12", kwargs[:force_scrape_every_hrs]
      true
    end.returns(Struct.new(:cache).new(nil))

    result = Distillator::CacheFetchCommand.new(
      params: {
        uri: "https://example.org/events#details",
        fetch_kind: "normal",
        absolute_src: "true",
        include_fragment: "true",
        force_scrape_every_hrs: "12"
      },
      fetcher: fetcher,
      guard: guard
    ).call

    assert_equal true, result.ok?
  end
end
