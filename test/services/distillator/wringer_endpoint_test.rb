require "test_helper"

class Distillator::WringerEndpointTest < ActiveSupport::TestCase
  test "staging resolves remote endpoint from DISTILLATOR_COMPATIBILITY_BASE_URL when config is nil" do
    endpoint = Distillator::WringerEndpoint.new(
      config: nil,
      env: ActiveSupport::StringInquirer.new("staging"),
      env_vars: {
        "DISTILLATOR_COMPATIBILITY_BASE_URL" => "https://footlight-wringer.herokuapp.com"
      }
    ).call

    assert_equal :remote_configured, endpoint.state
    assert_equal "https://footlight-wringer.herokuapp.com", endpoint.compatibility_base_url
    assert_equal "https://footlight-wringer.herokuapp.com", endpoint.legacy_lookup_base_url
    assert_equal "Current Wringer: Remote configured", endpoint.status_label
    assert_equal "https://footlight-wringer.herokuapp.com", endpoint.status_detail
  end

  test "staging resolves remote endpoint from DISTILLATOR_COMPAT_BASE_URL when config is nil" do
    endpoint = Distillator::WringerEndpoint.new(
      config: nil,
      env: ActiveSupport::StringInquirer.new("staging"),
      env_vars: {
        "DISTILLATOR_COMPAT_BASE_URL" => "https://footlight-wringer.herokuapp.com"
      }
    ).call

    assert_equal :remote_configured, endpoint.state
    assert_equal "https://footlight-wringer.herokuapp.com", endpoint.compatibility_base_url
    assert_equal "https://footlight-wringer.herokuapp.com", endpoint.legacy_lookup_base_url
  end

  test "staging is missing config when both compatibility env aliases are blank" do
    endpoint = Distillator::WringerEndpoint.new(
      config: nil,
      env: ActiveSupport::StringInquirer.new("staging"),
      env_vars: {}
    ).call

    assert_equal :missing_config, endpoint.state
    assert_nil endpoint.compatibility_base_url
    assert_nil endpoint.legacy_lookup_base_url
  end

  test "development still allows localhost by default when config is nil" do
    endpoint = Distillator::WringerEndpoint.new(
      config: nil,
      env: ActiveSupport::StringInquirer.new("development"),
      env_vars: {}
    ).call

    assert_equal :local_development, endpoint.state
    assert_equal "http://localhost:3000", endpoint.compatibility_base_url
    assert_equal "http://localhost:3009", endpoint.legacy_lookup_base_url
  end

  test "legacy wringer env overrides compatibility fallback when configured" do
    endpoint = Distillator::WringerEndpoint.new(
      config: nil,
      env: ActiveSupport::StringInquirer.new("staging"),
      env_vars: {
        "DISTILLATOR_COMPATIBILITY_BASE_URL" => "https://footlight-wringer.herokuapp.com",
        "LEGACY_WRINGER_BASE_URL" => "https://legacy.example"
      }
    ).call

    assert_equal :remote_configured, endpoint.state
    assert_equal "https://footlight-wringer.herokuapp.com", endpoint.compatibility_base_url
    assert_equal "https://legacy.example", endpoint.legacy_lookup_base_url
  end
end
