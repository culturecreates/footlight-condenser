require "test_helper"

class OptionsControllerTest < ActionDispatch::IntegrationTest
  include WebMock::API

  setup do
    WebMock.reset!
    Website.update_all(distillator_mode: "shadow")
  end

  test "navigation groups operational and configuration links and preserves global lists" do
    get options_path

    assert_response :success
    assert_select 'nav[aria-label="Condenser"]' do
      assert_select 'details' do |menus|
        assert_equal %w[Operations Configuration], menus.map { |menu| menu.at_css("summary").text }
        assert_equal [
          monitoring_path(seedurl: "all"), distillator_shadow_report_path, distillator_cache_index_path,
          sidekiq_web_path, databus_index_path, messages_path, test_api_websites_path,
          webpages_path(seedurl: "all"), sources_path(seedurl: "all"), statements_path(seedurl: "all")
        ], menus.first.css("a").map { |link| link["href"] }.take(10)
        assert_equal [properties_path, rdfs_classes_path, search_exceptions_path, jsonld_outputs_path],
          menus.last.css("a").map { |link| link["href"] }
      end
      assert_select '> a[href=?]', dsl_library_entries_path, text: "DSL Library"
      assert_select '> a[href=?][aria-current=page]', options_path, text: "Options"
    end
    assert_select 'nav[aria-label="Current website"]', count: 0
    assert_select '[data-condenser-header] a', text: "Trace on", count: 0

    get set_dsl_trace_options_path(state: "true")
    follow_redirect!
    assert_select '[data-condenser-header] a[href=?]', options_path(tab: "trace"), text: "Trace on"
  end

  test "navigation links to the configured Wringer without probing on page render" do
    configure_wringer("https://operator:secret@wringer-staging.example")
    probe = stub_request(:get, "https://wringer-staging.example/websites.json?per_page=1")

    get options_path

    assert_response :success
    assert_select '[data-condenser-header] a[href=?][title=?]', "https://wringer-staging.example", "https://wringer-staging.example" do
      assert_select 'span[data-wringer-reachability-url=?][role=status]', wringer_reachability_options_path, text: "Checking…"
    end
    assert_not_includes response.body, "operator:secret"
    assert_not_requested probe
  end

  test "Wringer reachability ignores the cached page's upstream HTTP status and body" do
    configure_wringer("https://operator:secret@wringer-staging.example")
    probe = stub_request(:get, "https://wringer-staging.example/websites.json?per_page=1")
      .with(basic_auth: ["operator", "secret"])
      .to_return(status: 200, body: '[{"http_response_code":403,"html":null}]')

    get wringer_reachability_options_path

    assert_response :success
    assert_equal({ "label" => "Reachable" }, response.parsed_body)
    assert_requested probe, times: 1
  end

  test "Wringer reachability reports Wringer's own HTTP error separately from a timeout" do
    configure_wringer("https://wringer-staging.example")
    stub_request(:get, "https://wringer-staging.example/websites.json?per_page=1")
      .to_return(status: 403).then.to_timeout
    Rails.stubs(:cache).returns(ActiveSupport::Cache::NullStore.new)

    get wringer_reachability_options_path
    assert_equal({ "label" => "Responded (HTTP 403)" }, response.parsed_body)

    get wringer_reachability_options_path
    assert_equal({ "label" => "Unreachable" }, response.parsed_body)
  end

  test "Wringer reachability caches a probe briefly for each configured Wringer" do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    configure_wringer("https://wringer-staging.example")
    staging_probe = stub_request(:get, "https://wringer-staging.example/websites.json?per_page=1")
      .to_return(status: 200, body: "[]").then.to_timeout
    production_probe = stub_request(:get, "https://wringer-production.example/websites.json?per_page=1")
      .to_return(status: 503)

    2.times { get wringer_reachability_options_path }
    assert_equal({ "label" => "Reachable" }, response.parsed_body)
    assert_requested staging_probe, times: 1

    travel 31.seconds do
      get wringer_reachability_options_path
      assert_equal({ "label" => "Unreachable" }, response.parsed_body)
      assert_requested staging_probe, times: 2
    end

    configure_wringer("https://wringer-production.example")
    get wringer_reachability_options_path
    assert_equal({ "label" => "Responded (HTTP 503)" }, response.parsed_body)
    assert_requested production_probe, times: 1
  end

  test "Wringer reachability skips an invalid URL" do
    configure_wringer("javascript:alert(1)")

    get options_path
    assert_includes response.body, "Missing or invalid Wringer URL"
    assert_select "span[data-wringer-reachability-url]", count: 0

    get wringer_reachability_options_path
    assert_equal({ "label" => "Missing or invalid Wringer URL" }, response.parsed_body)
  end

  test "Wringer reachability skips an unconfigured endpoint" do
    endpoint = Distillator::WringerEndpoint.new(config: nil, env: "staging", env_vars: {}).call
    Distillator::WringerEndpoint.stubs(:current).returns(endpoint)

    get wringer_reachability_options_path

    assert_equal({ "label" => "Missing or invalid Wringer URL" }, response.parsed_body)
  end

  test "options page does not render transition check queue button" do
    get options_path

    assert_response :success
    assert_not_includes @response.body, "Queue transition check"
  end

  test "options shows the current website monitoring setting and where to change it" do
    website = websites(:two)
    website.update!(monitorable: true)

    get options_path, params: { seedurl: website.seedurl }

    assert_response :success
    assert_select "p", text: /blocked source fetches, flagged DSL errors, and enrolled preprocessing problems/
    assert_select "p", text: /Website monitoring is on for #{Regexp.escape(website.name)}/
    assert_select 'a[href=?]', edit_website_path(website, anchor: "website-monitoring"), text: "Edit website monitoring"
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

    get options_path(tab: "transition")

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

    get options_path(tab: "transition")

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

    assert_redirected_to options_path(tab: "transition")
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

    assert_redirected_to options_path(tab: "transition")
    assert_equal "legacy", website.reload.distillator_mode
    assert_equal "Staging rollout repair can only run on staging.", flash[:alert]
  ensure
    ENV["DISTILLATOR_RUNTIME"] = nil
  end

  test "options page hides staging rollout repair button when invalid count is zero" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    ApplicationController.helpers.stubs(:get_wringer_url_per_environment).returns("http://wringer.example")

    get options_path(tab: "transition")

    assert_response :success
    assert_includes @response.body, "Invalid staging websites:"
    assert_not_includes @response.body, "Move invalid staging websites to Shadow"
  ensure
    ENV["DISTILLATOR_RUNTIME"] = nil
  end

  test "options subjects are addressable and only the selected subject is rendered" do
    Distillator::ProductionPreflight.expects(:call).never
    get options_path(tab: "trace")

    assert_select "nav[aria-label='Options subjects'] a", count: 4
    assert_select "nav a[aria-current=page]", text: "DSL trace"
    assert_select "#options-trace details summary", text: "Advanced display settings"
    assert_select "#options-monitoring, #options-transition, #options-connections", count: 0
    post options_path, params: { trace_code_tooltip_length: 180 }
    assert_redirected_to options_path(tab: "trace")
    assert_equal "180", cookies[:trace_code_tooltip_length]
  end

  test "inspection URLs retain site context and add an alternate cache link while keeping the configured Wringer" do
    configure_wringer("https://wringer-staging.example")
    website = websites(:two)
    page_url = "https://upstream.example/event"
    key = Distillator::WringerUrlKey.legacy(page_url).uri_key
    configured_lookup = stub_request(:get, "https://wringer-staging.example/websites.json").with(query: { term: key })
      .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })
    alternate_lookup = stub_request(:any, %r{https://wringer-comparison\.example/})

    patch connections_options_path, params: {
      console_inspection_url: " https://console-comparison.example/ ", wringer_inspection_url: "https://wringer-comparison.example/"
    }
    assert_redirected_to options_path(tab: "connections")
    get options_path(tab: "connections", seedurl: website.seedurl)
    assert_select 'nav[aria-label="Current website"] a[href=?]', "https://console-comparison.example/events?seedurl=#{website.seedurl}", text: /\AConsole/
    assert_select "a[href=?]", "https://wringer-staging.example"
    assert_select "input#wringer_inspection_url[value=?]", "https://wringer-comparison.example"

    get condenser_cache_compare_path(uri: page_url)
    assert_response :success
    assert_select "a[href=?]", "https://wringer-comparison.example/websites?#{ { term: key }.to_query }", text: "Inspect alternate Wringer cache"
    assert_requested configured_lookup, times: 1
    assert_not_requested alternate_lookup

    patch connections_options_path, params: { console_inspection_url: "", wringer_inspection_url: "" }
    get options_path(tab: "connections", seedurl: website.seedurl)
    assert_select "a[href*='console-comparison.example']", count: 0
    assert_select "input#wringer_inspection_url[value]", count: 0
  end

  test "invalid connection URLs leave the saved browser overrides intact" do
    patch connections_options_path, params: { console_inspection_url: "https://comparison.example" }
    patch connections_options_path, params: { console_inspection_url: "javascript:alert(1)", wringer_inspection_url: "https://unexpected.example" }
    assert_redirected_to options_path(tab: "connections")
    assert_includes flash[:alert], "Console needs an HTTP or HTTPS base URL"
    follow_redirect!
    assert_select "input#console_inspection_url[value=?]", "https://comparison.example"
    assert_select "input#wringer_inspection_url[value]", count: 0
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

  private

  def configure_wringer(base_url)
    config = ActiveSupport::OrderedOptions.new
    config.compatibility_base_url = "https://compat.example"
    config.legacy_wringer_base_url = base_url
    endpoint = Distillator::WringerEndpoint.new(config: config, env: "staging", env_vars: {}).call
    Distillator::WringerEndpoint.stubs(:current).returns(endpoint)
  end

end
