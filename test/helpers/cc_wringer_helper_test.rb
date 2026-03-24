require 'test_helper'

class CcWringerHelperTest < ActionView::TestCase


  test "should get wringer url for DEV" do
    expected_output = "http://localhost:3009"
    assert_equal expected_output, get_wringer_url_per_environment()
  end


  test "should convert url for wringer" do
    expected_output = "http://localhost:3009/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true"
    assert_equal expected_output, use_wringer("http://culturecreates.com", false)
  end

  test "should convert url for wringer using phantomjs" do
    expected_output = "http://localhost:3009/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true&use_phantomjs=true"
    assert_equal expected_output, use_wringer("http://culturecreates.com", true)
  end

  test "should convert url for wringer using json_post" do
    expected_output = "http://localhost:3009/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true&json_post=true"
    assert_equal expected_output, use_wringer("http://culturecreates.com", false, { json_post: true })
  end

  test "wringer_received_404 returns false when wringer call aborts" do
    stubs(:safe_wringer_call).returns(["abort_update", { error: "Wringer unreachable", error_type: "SocketError" }])
    assert_not wringer_received_404?("https://example.com")
  end

  test "safe_wringer_call handles connection error" do
    result = safe_wringer_call do
      raise Errno::ECONNREFUSED
    end

    assert_equal "abort_update", result.first
    assert_equal "wringer_unreachable", result.last[:error_type]
    assert result.last[:policy][:retry]
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
