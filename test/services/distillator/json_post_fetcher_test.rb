require "test_helper"

class Distillator::JsonPostFetcherTest < ActiveSupport::TestCase
  test "json_post uses post with empty body by default" do
    agent = mock("agent")
    agent.expects(:post).with("https://example.com/api", "", { "Content-Type" => "application/json" }).returns(:ok)

    assert_equal :ok, Distillator::JsonPostFetcher.call(agent: agent, url: "https://example.com/api", scrape_options: {})
  end

  test "json_post preserves explicit content type header" do
    agent = mock("agent")
    agent.expects(:post).with("https://example.com/api", "", { "Content-Type" => "application/custom+json" }).returns(:ok)

    assert_equal :ok, Distillator::JsonPostFetcher.call(
      agent: agent,
      url: "https://example.com/api",
      scrape_options: { headers: { "Content-Type" => "application/custom+json" } }
    )
  end
end
