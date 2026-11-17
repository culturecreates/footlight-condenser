require "test_helper"
require "webmock/minitest"

class Dsl::Support::UrlPlaceholdersTest < ActiveSupport::TestCase
  include DslRunnerTestHelper
  setup { @previous_origin = ENV["CONDENSER_PUBLIC_URL"] }
  teardown { ENV["CONDENSER_PUBLIC_URL"] = @previous_origin }

  test "same DSL resolves the configured environment after Ruby evaluation" do
    %w[https://staging.example https://production.example/ http://localhost:3000].each do |origin|
      ENV["CONDENSER_PUBLIC_URL"] = origin
      url = origin.delete_suffix("/") + "/statements.json?source=8039&seedurl=culturemauricie_lepointdevente-com-RList"
      stub_request(:get, url).to_return(status: 200, body: '[{"cache":"mapping"}]')
      runner, = build_runner
      result = runner.run('api="$$SELF_URL$$/statements.json?source=8039&seedurl=culturemauricie_lepointdevente-com-RList"')
      assert_equal [{"cache" => "mapping"}], result
      assert_requested :get, url, times: 1
    end
  end

  test "URL resolver preserves arrays fragments and query values" do
    ENV["CONDENSER_PUBLIC_URL"] = "https://staging.example/"
    assert_equal "https://staging.example/path?q=one#anchor", Dsl::Support::UrlResolver.extract([nil, "$$SELF_URL$$/path?q=one#anchor"])
    assert_equal "https://other.example/path", Dsl::Support::UrlResolver.extract("https://other.example/path")
  end

  test "missing or invalid configuration aborts rather than guessing production or the scraped website" do
    [nil, "https://example.org/path", "https://u:p@example.org", "https://example.org?x=1", "https://example.org#frag", "file:///tmp/x"].each do |origin|
      ENV["CONDENSER_PUBLIC_URL"] = origin
      runner, = build_runner(url: "https://scraped.example")
      result = runner.run('api="$$SELF_URL$$/statements.json"')
      assert_equal "abort_update", result.first
      assert_includes result.last[:error], "CONDENSER_PUBLIC_URL"
    end
  end

  test "URL steps use the same placeholder resolver without rewriting Ruby source" do
    ENV["CONDENSER_PUBLIC_URL"] = "https://staging.example"
    runner, = build_runner
    runner.expects(:fetch_result_for).with(url: "https://staging.example/data", render_js: false, scrape_options: {}).returns(
      {status: :ok, body: "<html><title>Local data</title></html>", wringer: {}})
    assert_equal ["Local data"], runner.run('url="$$SELF_URL$$/data";xpath=//title')
  end
end
