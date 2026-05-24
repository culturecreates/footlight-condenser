require 'test_helper'

class CcWringerHelperTest < ActionView::TestCase
  setup do
    Distillator::WringerRules.reset!
    @distillator_config = Rails.application.config.x.distillator
    @old_compatibility_base_url = @distillator_config.compatibility_base_url
    @old_legacy_wringer_base_url = @distillator_config.legacy_wringer_base_url
    @old_allow_localhost = @distillator_config.allow_localhost_compatibility
  end

  teardown do
    Distillator::WringerRules.reset!
    @distillator_config.compatibility_base_url = @old_compatibility_base_url
    @distillator_config.legacy_wringer_base_url = @old_legacy_wringer_base_url
    @distillator_config.allow_localhost_compatibility = @old_allow_localhost
  end


  test "development can default wringer urls to localhost" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("development"))
    @distillator_config.compatibility_base_url = nil
    @distillator_config.legacy_wringer_base_url = nil
    @distillator_config.allow_localhost_compatibility = true

    expected_output = "http://localhost:3009"
    assert_equal expected_output, get_wringer_url_per_environment()

    assert_equal "http://localhost:3000", distillator_compatibility_base_url
    assert_equal "http://localhost:3000/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true", use_wringer("http://culturecreates.com", false)
    assert_equal "http://localhost:3000/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true&use_phantomjs=true", use_wringer("http://culturecreates.com", true)
    assert_equal "http://localhost:3000/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true&json_post=true", use_wringer("http://culturecreates.com", false, { json_post: true })
    assert_equal "http://localhost:3000/websites/wring?uri=https%3A%2F%2Fculturecreates.com%2Fpeople%23gregory&format=raw&include_fragment=true", use_wringer("https://culturecreates.com/people#gregory", false)
  end

  test "use_wringer can explicitly target legacy live wringer fallback" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("development"))
    @distillator_config.compatibility_base_url = nil
    @distillator_config.legacy_wringer_base_url = nil
    @distillator_config.allow_localhost_compatibility = true

    expected_output = "http://localhost:3009/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true"
    assert_equal expected_output, use_wringer("http://culturecreates.com", false, { force_legacy: true })
  end

  test "staging without compatibility config does not silently use localhost" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = nil
    @distillator_config.legacy_wringer_base_url = nil
    @distillator_config.allow_localhost_compatibility = false

    assert_nil distillator_compatibility_base_url
    assert_nil get_wringer_url_per_environment
    assert_equal "Current Wringer: Missing staging config", current_wringer_endpoint.status_label
    assert_raises(ArgumentError) { use_wringer("http://culturecreates.com", false) }
  end

  test "staging with configured remote endpoint uses remote wringer urls" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = "https://compat.example"
    @distillator_config.legacy_wringer_base_url = "https://legacy.example"
    @distillator_config.allow_localhost_compatibility = false

    assert_equal "https://compat.example", distillator_compatibility_base_url
    assert_equal "https://legacy.example", get_wringer_url_per_environment
    assert_equal "Current Wringer: Remote configured", current_wringer_endpoint.status_label
    assert_equal "config.x.distillator.compatibility_base_url", current_wringer_endpoint.compatibility_source
    assert_equal "https://compat.example via config.x.distillator.compatibility_base_url", current_wringer_endpoint.status_detail
  end

  test "staging can resolve remote endpoint from DISTILLATOR_COMPAT_BASE_URL when config is nil" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = nil
    @distillator_config.legacy_wringer_base_url = nil
    @distillator_config.allow_localhost_compatibility = false
    old_compat_alias = ENV["DISTILLATOR_COMPAT_BASE_URL"]
    ENV["DISTILLATOR_COMPAT_BASE_URL"] = "https://footlight-wringer.herokuapp.com"

    assert_equal "https://footlight-wringer.herokuapp.com", distillator_compatibility_base_url
    assert_equal "https://footlight-wringer.herokuapp.com", get_wringer_url_per_environment
    assert_equal "Current Wringer: Remote configured", current_wringer_endpoint.status_label
    assert_equal "DISTILLATOR_COMPAT_BASE_URL", current_wringer_endpoint.compatibility_source
    assert_equal "https://footlight-wringer.herokuapp.com via DISTILLATOR_COMPAT_BASE_URL", current_wringer_endpoint.status_detail
  ensure
    ENV["DISTILLATOR_COMPAT_BASE_URL"] = old_compat_alias
  end

  test "staging can resolve remote endpoint from DISTILLATOR_COMPATIBILITY_BASE_URL alias when canonical is blank" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = nil
    @distillator_config.legacy_wringer_base_url = nil
    @distillator_config.allow_localhost_compatibility = false
    old_compatibility_alias = ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"]
    ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"] = "https://alias.example"

    assert_equal "https://alias.example", distillator_compatibility_base_url
    assert_equal "DISTILLATOR_COMPATIBILITY_BASE_URL", current_wringer_endpoint.compatibility_source
    assert_equal "https://alias.example via DISTILLATOR_COMPATIBILITY_BASE_URL", current_wringer_endpoint.status_detail
  ensure
    ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"] = old_compatibility_alias
  end

  test "canonical compat env wins over alias in helper status" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = nil
    @distillator_config.legacy_wringer_base_url = nil
    @distillator_config.allow_localhost_compatibility = false
    old_compat = ENV["DISTILLATOR_COMPAT_BASE_URL"]
    old_alias = ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"]
    ENV["DISTILLATOR_COMPAT_BASE_URL"] = "https://canonical.example"
    ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"] = "https://alias.example"

    assert_equal "https://canonical.example", distillator_compatibility_base_url
    assert_equal "DISTILLATOR_COMPAT_BASE_URL", current_wringer_endpoint.compatibility_source
    assert_equal "https://canonical.example via DISTILLATOR_COMPAT_BASE_URL", current_wringer_endpoint.status_detail
  ensure
    ENV["DISTILLATOR_COMPAT_BASE_URL"] = old_compat
    ENV["DISTILLATOR_COMPATIBILITY_BASE_URL"] = old_alias
  end

  test "staging configured remote endpoint can be marked unreachable without exposing credentials" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("staging"))
    @distillator_config.compatibility_base_url = "https://user:secret@compat.example/token"
    @distillator_config.legacy_wringer_base_url = "https://legacy.example"
    @distillator_config.allow_localhost_compatibility = false

    endpoint = current_wringer_endpoint(last_error: "connection refused")

    assert_equal :unreachable, endpoint.state
    assert_equal "Current Wringer: Unreachable", endpoint.status_label
    assert_equal "last lookup failed", endpoint.status_detail
    assert_equal "config.x.distillator.compatibility_base_url", endpoint.compatibility_source
    assert_equal "https://user:secret@compat.example/token", endpoint.compatibility_base_url
  end

  test "normalized_fetch_url strips fragment without affecting wringer uri target" do
    assert_equal "https://culturecreates.com/people", normalized_fetch_url("https://culturecreates.com/people#gregory")
    assert_equal "https://culturecreates.com/people#gregory", wringer_uri_target("https://culturecreates.com/people#gregory")
  end

  test "wringer_received_404 uses local distillator cache by default" do
    key = Distillator::WringerUrlKey.call("https://example.com", include_fragment: true)
    Distillator::FetchCache.create!(
      uri_key: key.uri_key,
      normalized_url: key.normalized_url,
      http_response_code: 404,
      scrape_date: Time.zone.now
    )

    assert wringer_received_404?("https://example.com")
  end

  test "wringer_received_404 returns false when explicit legacy fallback aborts" do
    previous = ENV[Distillator::WringerEndpoint::LEGACY_WRINGER_FALLBACK_ENV]
    ENV[Distillator::WringerEndpoint::LEGACY_WRINGER_FALLBACK_ENV] = "true"
    stubs(:safe_wringer_call).returns(["abort_update", { error: "Wringer unreachable", error_type: "SocketError" }])

    assert_not wringer_received_404?("https://example.com")
  ensure
    ENV[Distillator::WringerEndpoint::LEGACY_WRINGER_FALLBACK_ENV] = previous
  end

  test "safe_wringer_call handles connection error" do
    result = safe_wringer_call do
      raise Errno::ECONNREFUSED
    end

    assert_equal "abort_update", result.first
    assert_equal "wringer_unreachable", result.last[:error_type]
    assert result.last[:policy][:retry]
  end

  test "safe_wringer_call preserves explicit false retry and cache values" do
    rules = {
      "empty_body" => {
        "match" => { "body_blank" => true },
        "policy" => {
          "action" => "abort_update",
          "retry" => false,
          "cache" => false,
          "delete" => false,
          "error_code" => "empty_body"
        }
      }
    }

    stubs(:wringer_rules).returns(rules.to_a)

    fake_response = Struct.new(:code, :body, :uri).new(
      200,
      nil,
      URI("https://example.com/empty")
    )

    result = safe_wringer_call { fake_response }

    assert_equal "abort_update", result.first
    assert_equal false, result.last[:retry]
    assert_equal false, result.last[:cache]
    assert_equal false, result.last[:policy]["delete"]
  end

  # test "should call wringer to condense and add webpage to knowledge graph" do
  #   expected_output = ""
  #   url = "https://www.dansedanse.ca/en/dada-masilo-dance-factory-johannesburg-giselle"
  #   graph_uri = "http://artsdata.ca"
  #   jsonld = {}
  #   assert_equal expected_output, update_jsonld_on_wringer(url, graph_uri, jsonld)
  # end
  #
  #
  # test "should call wringer to delete condensed file" do
  #   expected_output = ""
  #   url = "https://www.dansedanse.ca/en/dada-masilo-dance-factory-johannesburg-giselle"
  #   graph_uri = "http://artsdata.ca"
  #   jsonld = {}
  #   assert_equal expected_output, update_jsonld_on_wringer(url, graph_uri, jsonld)
  # end

  # -------------------------
  # WRINGER RULE ENGINE TESTS
  # -------------------------

  test "detects redirect_to_listing via final_url" do
    rules = {
      "redirect_to_listing" => {
        "match" => {
          "final_url_patterns" => ["/events$", "/$"]
        },
        "policy" => {
          "action" => "abort_update",
          "retry" => false,
          "cache" => false,
          "delete" => true,
          "error_code" => "redirect_to_listing"
        }
      }
    }

    stubs(:wringer_rules).returns(rules.to_a)

    response = {
      body: "<html>listing</html>",
      http_code: 200,
      final_url: "https://example.com/events"
    }

    result = wringer_system_error?(response)

    assert_not_nil result
    assert_equal "redirect_to_listing", result[:error_type]
    assert result[:policy]["delete"]
    assert_not result[:policy]["retry"]
  end


  test "does not trigger redirect_to_listing for valid event page" do
    rules = {
      "redirect_to_listing" => {
        "match" => {
          "final_url_patterns" => ["/events$", "/$"]
        },
        "policy" => {
          "error_code" => "redirect_to_listing"
        }
      }
    }

    stubs(:wringer_rules).returns(rules.to_a)

    response = {
      body: "<html>event page</html>",
      http_code: 200,
      final_url: "https://example.com/events/123"
    }

    result = wringer_system_error?(response)

    assert_nil result
  end


  test "http_404 rule still works" do
    rules = {
      "http_404" => {
        "match" => { "http_code" => 404 },
        "policy" => {
          "error_code" => "http_404",
          "retry" => false
        }
      }
    }

    stubs(:wringer_rules).returns(rules.to_a)

    response = {
      body: "Not found",
      http_code: 404,
      final_url: "https://example.com/foo"
    }

    result = wringer_system_error?(response)

    assert_not_nil result
    assert_equal "http_404", result[:error_type]
  end


  test "rule ordering prioritizes redirect over generic rules" do
    rules = {
      "redirect_to_listing" => {
        "match" => {
          "final_url_patterns" => ["/events$"]
        },
        "policy" => {
          "error_code" => "redirect_to_listing"
        }
      },
      "http_404" => {
        "match" => { "http_code" => 200 }, # fake overlap
        "policy" => {
          "error_code" => "http_404"
        }
      }
    }

    stubs(:wringer_rules).returns(rules.to_a)

    response = {
      body: "something",
      http_code: 200,
      final_url: "https://example.com/events"
    }

    result = wringer_system_error?(response)

    assert_equal "redirect_to_listing", result[:error_type]
  end

  test "wringer_system_error prefers severity-aware primary issue" do
    response = {
      body: "",
      http_code: 500,
      final_url: "https://example.org/failure",
      hints: ["empty_body"],
      signals: {}
    }

    issue = wringer_system_error?(response)

    assert_equal "http_server_error", issue[:error_type]
  end


  test "safe_wringer_call returns abort_update when redirect rule matches" do
    rules = {
      "redirect_to_listing" => {
        "match" => {
          "final_url_patterns" => ["/events$"]
        },
        "policy" => {
          "action" => "abort_update",
          "retry" => false,
          "delete" => true,
          "error_code" => "redirect_to_listing"
        }
      }
    }

    stubs(:wringer_rules).returns(rules.to_a)

    fake_response = Struct.new(:code, :body, :uri).new(
      200,
      "<html>listing</html>",
      URI("https://example.com/events")
    )

    result = safe_wringer_call { fake_response }

    assert_equal "abort_update", result.first
    assert_equal "redirect_to_listing", result.last[:error_type]
  end

  test "safe_wringer_call returns body when no rule matches" do
    stubs(:wringer_rules).returns([])

    fake_response = Struct.new(:code, :body, :uri).new(
      200,
      "<html>event</html>",
      URI("https://example.com/events/123")
    )

    result = safe_wringer_call { fake_response }

    assert_equal "<html>event</html>", result
  end

  test "safe_wringer_call works when wringer config is missing" do
    CcWringerHelper.instance_variable_set(:@wringer_rules, nil)
    Rails.application.stubs(:config_for).with(:wringer).returns(nil)

    fake_response = Struct.new(:code, :body, :uri).new(
      200,
      "<html>event</html>",
      URI("https://example.com/events/123")
    )

    result = safe_wringer_call { fake_response }

    assert_equal "<html>event</html>", result
  end

  test "safe_wringer_call preserves false return value" do
    stubs(:wringer_rules).returns([])

    result = safe_wringer_call { false }

    assert_equal false, result
    assert_instance_of FalseClass, result
  end

  test "safe_wringer_call preserves true return value" do
    stubs(:wringer_rules).returns([])

    result = safe_wringer_call { true }

    assert_equal true, result
    assert_instance_of TrueClass, result
  end

  test "safe_wringer_call preserves plain string return value" do
    stubs(:wringer_rules).returns([])

    result = safe_wringer_call { "hello" }

    assert_equal "hello", result
  end

  test "safe_wringer_call can return normalized response hash" do
    stubs(:wringer_rules).returns([])

    fake_response = Struct.new(:code, :body, :uri).new(
      302,
      "<html>redirect</html>",
      URI("https://example.com/events")
    )

    result = safe_wringer_call(normalize_response: true) { fake_response }

    assert_equal(
      { body: "<html>redirect</html>", http_code: 302, final_url: "https://example.com/events" },
      result
    )
  end

  test "matches only when all conditions are satisfied" do
    rules = {
      "complex_rule" => {
        "match" => {
          "http_code" => 200,
          "body_contains" => ["listing"],
          "final_url_patterns" => ["/events$"]
        },
        "policy" => {
          "error_code" => "complex_rule"
        }
      }
    }

    stubs(:wringer_rules).returns(rules.to_a)

    response = {
      body: "<html>listing</html>",
      http_code: 200,
      final_url: "https://example.com/events"
    }

    result = wringer_system_error?(response)

    assert_equal "complex_rule", result[:error_type]
  end

  test "safe_wringer_call respects custom action from policy" do
    rules = {
      "custom_action_rule" => {
        "match" => {
          "http_code" => 200
        },
        "policy" => {
          "action" => "skip",
          "error_code" => "custom_action"
        }
      }
    }

    stubs(:wringer_rules).returns(rules.to_a)

    fake_response = Struct.new(:code, :body, :uri).new(
      200,
      "<html>whatever</html>",
      URI("https://example.com/foo")
    )

    result = safe_wringer_call { fake_response }

    assert_equal "skip", result.first
    assert_equal "custom_action", result.last[:error_type]
  end

  test "safe_wringer_call preserves redirect delete policy" do
    response = Struct.new(:code, :body, :uri).new(
      200,
      '<html><div class="jet-listing-dynamic-field">listing</div></html>',
      URI("https://example.org/events")
    )

    result = safe_wringer_call { response }

    assert_equal "abort_update", result.first
    assert_equal "redirect_to_listing", result.last[:error_type]
    assert_not result.last[:retry]
    assert_not result.last[:cache]
    assert result.last[:delete]
  end
  
  test "invalid regex pattern does not crash rule engine" do
    rules = {
      "bad_regex" => {
        "match" => {
          "final_url_patterns" => ["*invalid["]
        },
        "policy" => {
          "error_code" => "bad_regex"
        }
      }
    }

    stubs(:wringer_rules).returns(rules.to_a)

    response = {
      body: "ok",
      http_code: 200,
      final_url: "https://example.com/events"
    }

    result = wringer_system_error?(response)

    assert_nil result
  end
end
