require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  setup do
    @distillator_config = Rails.application.config.x.distillator
    @old_compatibility_base_url = @distillator_config.compatibility_base_url
    @old_legacy_wringer_base_url = @distillator_config.legacy_wringer_base_url
    @old_allow_localhost = @distillator_config.allow_localhost_compatibility
  end

  teardown do
    @distillator_config.compatibility_base_url = @old_compatibility_base_url
    @distillator_config.legacy_wringer_base_url = @old_legacy_wringer_base_url
    @distillator_config.allow_localhost_compatibility = @old_allow_localhost
  end

  test "current wringer status text shows missing staging config explicitly" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = nil
    @distillator_config.legacy_wringer_base_url = nil
    @distillator_config.allow_localhost_compatibility = false
    ENV.delete("DISTILLATOR_COMPAT_BASE_URL")
    ENV.delete("DISTILLATOR_COMPATIBILITY_BASE_URL")
    endpoint = Distillator::WringerEndpoint.current

    assert_equal :missing_config, endpoint.state
    assert_equal "Current Wringer: Missing staging config - comparisons disabled", current_wringer_status_text
  end

  test "current wringer status reports configuration independently of a recorded upstream rejection" do
    Distillator::TransitionEvidence.create!(website: websites(:one), url: "https://example.org/event", check_kind: "fetch_parity",
      checked_at: Time.current, status: "failed",
      details: {
        "legacy_lookup_error" => "Fresh Wringer scrape did not confirm HTTP 2xx (403); cached HTML rejected",
        "legacy_lookup_status" => "unreachable",
        "representative_url_results" => [{ "legacy_fetch" => { "response_http_code" => 200, "upstream_http_code" => 403 } }]
      }
    )
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = "https://user:secret@compat.example/token"
    @distillator_config.legacy_wringer_base_url = "https://legacy.example"
    @distillator_config.allow_localhost_compatibility = false

    assert_equal "Current Wringer: Remote configured - https://compat.example via config.x.distillator.compatibility_base_url", current_wringer_status_text
  end

  test "current wringer status text sanitizes configured remote endpoint" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = "https://user:secret@compat.example/token"
    @distillator_config.legacy_wringer_base_url = "https://legacy.example"
    @distillator_config.allow_localhost_compatibility = false

    assert_equal "Current Wringer: Remote configured - https://compat.example via config.x.distillator.compatibility_base_url", current_wringer_status_text
  end

  test "current wringer status text uses DISTILLATOR_COMPATIBILITY_BASE_URL when config is nil" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = nil
    @distillator_config.legacy_wringer_base_url = nil
    @distillator_config.allow_localhost_compatibility = false
    old_compatibility_alias = ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"]
    ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"] = "https://footlight-wringer.herokuapp.com"

    assert_equal "Current Wringer: Remote configured - https://footlight-wringer.herokuapp.com via DISTILLATOR_COMPATIBILITY_BASE_URL", current_wringer_status_text
  ensure
    ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"] = old_compatibility_alias
  end

  test "current wringer status text shows canonical compat env source when both aliases are set" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = nil
    @distillator_config.legacy_wringer_base_url = nil
    @distillator_config.allow_localhost_compatibility = false
    old_compat = ENV["DISTILLATOR_COMPAT_BASE_URL"]
    old_alias = ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"]
    ENV["DISTILLATOR_COMPAT_BASE_URL"] = "https://canonical.example"
    ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"] = "https://alias.example"

    assert_equal "Current Wringer: Remote configured - https://canonical.example via DISTILLATOR_COMPAT_BASE_URL", current_wringer_status_text
  ensure
    ENV["DISTILLATOR_COMPAT_BASE_URL"] = old_compat
    ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"] = old_alias
  end

end
