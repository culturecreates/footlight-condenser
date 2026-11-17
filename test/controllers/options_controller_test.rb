require "test_helper"

class OptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Website.update_all(distillator_mode: "shadow")
  end

  test "options page shows transition report link between cache and options in internal navigation" do
    get options_path

    assert_response :success
    assert_match %r{/distillator/cache.*?/distillator/shadow_report.*?/options}m, @response.body
    assert_match '>cache<', @response.body
    assert_match '>Transition report<', @response.body
    assert_match '>options<', @response.body
  end

  test "options page does not render transition check queue button" do
    get options_path

    assert_response :success
    assert_not_includes @response.body, "Queue transition check"
  end

  test "options page shows preflight pass fail summary and staging rollout policy failure" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    Website.create!(
      name: "Legacy options website",
      seedurl: "legacy-options-website",
      graph_name: "https://legacy-options-website.example/graph",
      default_language: "en",
      distillator_mode: "legacy"
    )
    ApplicationController.helpers.stubs(:get_wringer_url_per_environment).returns("http://wringer.example")

    get options_path

    assert_response :success
    assert_includes @response.body, "Status:</strong>"
    assert_includes @response.body, "FAIL"
    assert_includes @response.body, "Staging requires every website to be Shadow or Active."
  ensure
    ENV["DISTILLATOR_RUNTIME"] = nil
  end

  test "options page shows staging rollout repair dry run and apply button on staging" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    website = Website.create!(
      name: "Legacy repair options website",
      seedurl: "legacy-repair-options-website",
      graph_name: "https://legacy-repair-options-website.example/graph",
      default_language: "en",
      distillator_mode: "legacy"
    )
    ApplicationController.helpers.stubs(:get_wringer_url_per_environment).returns("http://wringer.example")

    get options_path

    assert_response :success
    assert_includes @response.body, "Invalid staging websites:"
    assert_includes @response.body, "Dry run"
    assert_includes @response.body, website.name
    assert_includes @response.body, "This action only runs on staging."
    assert_includes @response.body, "It records rollout events."
    assert_includes @response.body, "It changes only invalid modes to Shadow; Active and Shadow are unchanged."
    assert_includes @response.body, "Move invalid staging websites to Shadow"
    assert_includes @response.body, "Move all invalid staging websites to Shadow?"
  ensure
    ENV["DISTILLATOR_RUNTIME"] = nil
  end

  test "options apply staging rollout repair moves invalid sites to shadow" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    website = Website.create!(
      name: "Legacy repair apply options website",
      seedurl: "legacy-repair-apply-options-website",
      graph_name: "https://legacy-repair-apply-options-website.example/graph",
      default_language: "en",
      distillator_mode: "legacy"
    )

    post repair_staging_rollout_options_path

    assert_redirected_to options_path
    assert_equal "shadow", website.reload.distillator_mode
    follow_redirect!
    assert_includes @response.body, "Staging rollout repair moved 1 websites to Shadow. 0 unrepaired."
  ensure
    ENV["DISTILLATOR_RUNTIME"] = nil
  end

  test "options apply staging rollout repair outside staging redirects with alert and changes nothing" do
    ENV["DISTILLATOR_RUNTIME"] = "production"
    website = Website.create!(
      name: "Legacy repair blocked options website",
      seedurl: "legacy-repair-blocked-options-website",
      graph_name: "https://legacy-repair-blocked-options-website.example/graph",
      default_language: "en",
      distillator_mode: "legacy"
    )
    Distillator::StagingRolloutRepair.expects(:call).never

    post repair_staging_rollout_options_path

    assert_redirected_to options_path
    assert_equal "legacy", website.reload.distillator_mode
    assert_equal "Staging rollout repair can only run on staging.", flash[:alert]
  ensure
    ENV["DISTILLATOR_RUNTIME"] = nil
  end

  test "options page hides staging rollout repair button when invalid count is zero" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    ApplicationController.helpers.stubs(:get_wringer_url_per_environment).returns("http://wringer.example")

    get options_path

    assert_response :success
    assert_includes @response.body, "Invalid staging websites:"
    assert_not_includes @response.body, "Move invalid staging websites to Shadow"
  ensure
    ENV["DISTILLATOR_RUNTIME"] = nil
  end

  test "set_trace_view_mode stores cookie and redirects back" do
    post set_trace_view_mode_path(2), headers: { "HTTP_REFERER" => options_url }

    assert_redirected_to options_url
    assert_equal "2", cookies[:trace_view_mode]
  end
  test "monitoring mailbox persists independently of browser cookies and can be disabled" do
    patch monitoring_options_path, params: { monitoring_setting: { mailbox: " monitor@example.org " } }
    assert_redirected_to options_path
    assert_equal "monitor@example.org", MonitoringSetting.current.mailbox
    get options_path
    assert_select "input[name='monitoring_setting[mailbox]'][value='monitor@example.org']"
    patch monitoring_options_path, params: { monitoring_setting: { mailbox: "" } }
    assert_nil MonitoringSetting.current.mailbox
  end

  test "invalid monitoring mailbox preserves the previous value" do
    MonitoringSetting.current.update!(mailbox: "monitor@example.org")
    patch monitoring_options_path, params: { monitoring_setting: { mailbox: "one@example.org, two@example.org" } }
    assert_redirected_to options_path
    assert_equal "monitor@example.org", MonitoringSetting.current.mailbox
    assert flash[:alert].present?
  end

  test "weekly pulse checkbox persists without changing the mailbox or daily limit" do
    setting = MonitoringSetting.current
    setting.update!(mailbox: "monitor@example.org", last_digest_on: Date.current)
    patch monitoring_options_path, params: { monitoring_setting: { weekly_pulse_enabled: "0" } }
    assert_redirected_to options_path
    assert_not setting.reload.weekly_pulse_enabled?
    assert_equal "monitor@example.org", setting.mailbox
    assert_equal Date.current, setting.last_digest_on
    patch monitoring_options_path, params: { monitoring_setting: { weekly_pulse_enabled: "1" } }
    assert setting.reload.weekly_pulse_enabled?
    get options_path
    assert_select "input[type=checkbox][name='monitoring_setting[weekly_pulse_enabled]'][checked]"
  end

end
