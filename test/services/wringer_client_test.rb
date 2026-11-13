require "test_helper"
require "minitest/mock"

class WringerClientTest < ActiveSupport::TestCase
  test "preserves DSL wringer metadata in signals" do
    fake_dsl_result = {
      body: "<html>ok</html>",
      wringer: {
        error_type: "system_cloudflare",
        retry: true,
        cache: false,
        signals: { network_status: "ok" }
      }
    }

    client = WringerClient.new("http://example.com")

    client.stub(:call_wringer, fake_dsl_result) do
      result = client.fetch

      assert_equal "system_cloudflare", result[:signals][:error_type]
      assert_equal true, result[:signals][:retry]
      assert_equal false, result[:signals][:cache]
      assert_equal "ok", result[:signals][:signals][:network_status]
    end
  end
end
