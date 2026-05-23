require "test_helper"

class Distillator::CacheLinkResolverTest < ActiveSupport::TestCase
  setup do
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    @old_replay_fetch = ENV["REPLAY_FETCH"]
    ApplicationController.helpers.stubs(:get_wringer_url_per_environment).returns("http://wringer.example")
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
