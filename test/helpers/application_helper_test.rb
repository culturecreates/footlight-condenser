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
    Distillator::TransitionEvidence.stubs(:latest_legacy_lookup_error).returns(nil)

    endpoint = Distillator::WringerEndpoint.current

    assert_equal :missing_config, endpoint.state
    assert_equal "Current Wringer: Missing staging config - comparisons disabled", current_wringer_status_text
  end

  test "current wringer status text shows unreachable endpoint after latest lookup failure" do
    record = stub(
      details: {
        "legacy_lookup_error" => "Connection refused",
        "legacy_lookup_status" => "unreachable",
        "reason" => "legacy_lookup_unreachable"
      }
    )
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = "https://user:secret@compat.example/token"
    @distillator_config.legacy_wringer_base_url = "https://legacy.example"
    @distillator_config.allow_localhost_compatibility = false

    Distillator::TransitionEvidence.stubs(:latest_legacy_lookup_error).returns(record)

    assert_equal "Current Wringer: Unreachable - last lookup failed", current_wringer_status_text
  end

  test "current wringer status text sanitizes configured remote endpoint" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = "https://user:secret@compat.example/token"
    @distillator_config.legacy_wringer_base_url = "https://legacy.example"
    @distillator_config.allow_localhost_compatibility = false
    Distillator::TransitionEvidence.stubs(:latest_legacy_lookup_error).returns(nil)

    assert_equal "Current Wringer: Remote configured - https://compat.example via config.x.distillator.compatibility_base_url", current_wringer_status_text
  end

  test "current wringer status text uses DISTILLATOR_COMPATIBILITY_BASE_URL when config is nil" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = nil
    @distillator_config.legacy_wringer_base_url = nil
    @distillator_config.allow_localhost_compatibility = false
    old_compatibility_alias = ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"]
    ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"] = "https://footlight-wringer.herokuapp.com"
    Distillator::TransitionEvidence.stubs(:latest_legacy_lookup_error).returns(nil)

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
    Distillator::TransitionEvidence.stubs(:latest_legacy_lookup_error).returns(nil)

    assert_equal "Current Wringer: Remote configured - https://canonical.example via DISTILLATOR_COMPAT_BASE_URL", current_wringer_status_text
  ensure
    ENV["DISTILLATOR_COMPAT_BASE_URL"] = old_compat
    ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"] = old_alias
  end

  test "missing config transition evidence does not mark a configured endpoint as unreachable" do
    record = stub(
      details: {
        "legacy_lookup_error" => "missing_config",
        "legacy_lookup_status" => "missing_config",
        "reason" => "legacy_lookup_missing_config"
      }
    )
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = "https://user:secret@compat.example/token"
    @distillator_config.legacy_wringer_base_url = "https://legacy.example"
    @distillator_config.allow_localhost_compatibility = false
    Distillator::TransitionEvidence.stubs(:latest_legacy_lookup_error).returns(record)

    assert_equal "Current Wringer: Remote configured - https://compat.example via config.x.distillator.compatibility_base_url", current_wringer_status_text
  end
end
