require "test_helper"

class Distillator::CacheLinkResolverTest < ActiveSupport::TestCase
  setup do
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    @old_replay_fetch = ENV["REPLAY_FETCH"]
    Distillator::WringerEndpoint.stubs(:current).returns(
      Distillator::WringerEndpoint::Result.new(
        compatibility_base_url: "http://compat.example",
        legacy_lookup_base_url: "http://wringer.example",
        state: :remote_configured,
        status_label: "Current Wringer: Remote configured",
        status_detail: "http://wringer.example"
      )
    )
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
    ENV["REPLAY_FETCH"] = @old_replay_fetch
  end

  test "uses safe legacy links without website context even when env requests Distillator" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    assert_equal :legacy, Distillator::CacheLinkResolver.call(url: "http://example.org/page")[:mode]

    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    internal = Distillator::CacheLinkResolver.call(url: "http://example.org/page")
    assert_equal :legacy, internal[:mode]
    assert_equal :legacy, internal[:rollout_mode]
    assert_equal :wringer, internal[:active_backend]
    assert_equal :default, internal[:source]
    assert_equal internal[:legacy_cache_url], internal[:active_cache_url]

    ENV["DISTILLATOR_FETCH_MODE"] = "shadow"
    shadow = Distillator::CacheLinkResolver.call(url: "http://example.org/page")
    assert_equal :legacy, shadow[:mode]
    assert_equal :legacy, shadow[:rollout_mode]
    assert_equal :wringer, shadow[:active_backend]
    assert_equal :default, shadow[:source]
    assert_equal shadow[:legacy_cache_url], shadow[:active_cache_url]

    ENV["REPLAY_FETCH"] = "fixture"
    replay = Distillator::CacheLinkResolver.call(url: "http://example.org/page")
    assert_equal :replay, replay[:mode]
    assert_equal "Diagnostic mode only. Do not treat this as a production state.", replay[:warning]

    invalid = Distillator::CacheLinkResolver.call(url: "http://[invalid")
    assert_equal true, invalid[:disabled]
  end

  test "explicit active alias compatibility and shadow modes remain available for diagnostics" do
    internal = Distillator::CacheLinkResolver.call(url: "http://example.org/page", mode: :internal)
    assert_equal "Open active cache", internal[:label]
    assert_equal :active, internal[:mode]
    assert_equal :active, internal[:rollout_mode]
    assert_equal :condenser, internal[:active_backend]
    assert_equal :explicit, internal[:source]

    shadow = Distillator::CacheLinkResolver.call(url: "http://example.org/page", mode: :shadow)
    assert_equal "Open active cache", shadow[:label]
    assert_equal :shadow, shadow[:mode]
    assert_equal :shadow, shadow[:rollout_mode]
    assert_equal :wringer, shadow[:active_backend]
    assert_equal :explicit, shadow[:source]
    assert_equal 2, shadow[:secondary_links].length
    assert_match "/condenser/cache/compare?uri=", shadow[:secondary_links].first[:url]
  end

  test "preserves include fragment behavior in generated cache links" do
    payload = Distillator::CacheLinkResolver.call(url: "http://example.org/page#frag", include_fragment: true, mode: :internal)

    assert_includes payload[:distillator_cache_url], "term=http%3A%2F%2Fexample.org%2Fpage%23frag"
  end

  test "json_post keeps condenser as active cache path in active alias mode" do
    payload = Distillator::CacheLinkResolver.call(
      url: "http://example.org/api",
      mode: :internal,
      scrape_options: { json_post: true }
    )

    assert_equal "Open active cache", payload[:label]
    assert_equal payload[:distillator_cache_url], payload[:active_cache_url]
    assert_nil payload[:warning]
  end

  test "website rollout mode wins over global default when website context is present" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    website = websites(:one)
    website.update!(distillator_mode: "active")

    payload = Distillator::CacheLinkResolver.call(url: "http://example.org/page", website: website)

    assert_equal :active, payload[:mode]
    assert_equal :active, payload[:rollout_mode]
    assert_equal :condenser, payload[:active_backend]
    assert_equal :website, payload[:source]
    assert_equal payload[:distillator_cache_url], payload[:active_cache_url]
    assert_equal "Inspect legacy Wringer", payload[:secondary_links].first[:label]
  end

  test "shadow website keeps wringer active and exposes comparison link" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    website = websites(:one)
    website.update!(distillator_mode: "shadow")

    payload = Distillator::CacheLinkResolver.call(url: "http://example.org/page", website: website)

    assert_equal :shadow, payload[:mode]
    assert_equal :shadow, payload[:rollout_mode]
    assert_equal :wringer, payload[:active_backend]
    assert_equal :website, payload[:source]
    assert_equal payload[:legacy_cache_url], payload[:active_cache_url]
    assert_equal "Compare Condenser vs Wringer", payload[:secondary_links].first[:label]
    assert_match "/condenser/cache/compare?uri=", payload[:secondary_links].first[:url]
    assert_equal "Wringer serves production while Condenser is checked in the background.", payload[:warning]
  end

  test "compare link preserves single escaped uri parameter for query urls" do
    payload = Distillator::CacheLinkResolver.call(url: "https://example.org/evenements/caf%C3%A9?lang=fr&category=arts%20vivants", mode: :shadow)

    assert_includes payload[:compare_url], "uri=https%3A%2F%2Fexample.org%2Fevenements%2Fcaf%25C3%25A9%3Flang%3Dfr%26category%3Darts%2520vivants"
    refute_includes payload[:compare_url], "uri=https%253A"
  end

  test "missing wringer endpoint keeps condenser links but does not build malformed legacy links" do
    Distillator::WringerEndpoint.stubs(:current).returns(
      Distillator::WringerEndpoint::Result.new(
        compatibility_base_url: nil,
        legacy_lookup_base_url: nil,
        compatibility_source: nil,
        state: :missing_config,
        status_label: "Current Wringer: Missing staging config",
        status_detail: "comparisons disabled"
      )
    )

    payload = Distillator::CacheLinkResolver.call(url: "http://example.org/page", mode: :shadow)

    assert_nil payload[:legacy_cache_url]
    assert_nil payload[:active_cache_url]
    assert_equal [{ label: "Open Condenser cache", url: payload[:distillator_cache_url] }], payload[:secondary_links]
    assert_equal "Wringer endpoint missing; comparison unavailable.", payload[:warning]
  end

  test "legacy mode with missing wringer endpoint still exposes condenser cache only" do
    Distillator::WringerEndpoint.stubs(:current).returns(
      Distillator::WringerEndpoint::Result.new(
        compatibility_base_url: nil,
        legacy_lookup_base_url: nil,
        compatibility_source: nil,
        state: :missing_config,
        status_label: "Current Wringer: Missing staging config",
        status_detail: "comparisons disabled"
      )
    )

    payload = Distillator::CacheLinkResolver.call(url: "http://example.org/page", mode: :legacy)

    assert_nil payload[:legacy_cache_url]
    assert_nil payload[:active_cache_url]
    assert_equal [{ label: "Open Condenser cache", url: payload[:distillator_cache_url] }], payload[:secondary_links]
    assert_equal "Wringer endpoint missing; comparison unavailable.", payload[:warning]
  end

  test "legacy mode keeps wringer active and exposes distillator cache as secondary link" do
    payload = Distillator::CacheLinkResolver.call(url: "http://example.org/page", mode: :legacy)

    assert_equal payload[:legacy_cache_url], payload[:active_cache_url]
    assert_equal "Open Condenser cache", payload[:secondary_links].first[:label]
    assert_equal payload[:distillator_cache_url], payload[:secondary_links].first[:url]
    assert_equal "Wringer serves production.", payload[:warning]
  end

  test "active mode does not duplicate condenser cache as a secondary link" do
    payload = Distillator::CacheLinkResolver.call(url: "http://example.org/page", mode: :internal)

    assert_equal payload[:distillator_cache_url], payload[:active_cache_url]
    refute_includes payload[:secondary_links].map { |link| link[:label] }, "Open Condenser cache"
  end
end
