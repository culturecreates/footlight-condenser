require "test_helper"

class CacheLinkRenderingTest < ActionView::TestCase
  include ApplicationHelper
  include WebsitesHelper
  include WebpagesHelper
  include StatementsHelper
  include SourcesHelper
  include OperatorContextHelper

  setup do
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    Distillator::WringerEndpoint.stubs(:current).returns(
      Distillator::WringerEndpoint::Result.new(
        compatibility_base_url: "https://wringer.example",
        legacy_lookup_base_url: "https://wringer.example",
        compatibility_source: Distillator::WringerEndpoint::CANONICAL_COMPATIBILITY_ENV,
        state: :remote_configured,
        status_label: "Current Wringer: Remote configured",
        status_detail: "https://wringer.example"
      )
    )
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
  end

  test "common surfaces agree on cache links for legacy shadow and active rollout" do
    ENV["DISTILLATOR_FETCH_MODE"] = "active"

    {
      legacy: { mode: "legacy", active_backend: :wringer, secondary_labels: ["Open Condenser cache"] },
      shadow: { mode: "shadow", active_backend: :wringer, secondary_labels: ["Compare Condenser vs Wringer", "Open Condenser cache"] },
      active: { mode: "active", active_backend: :condenser, secondary_labels: ["Inspect legacy Wringer", "Compare Condenser vs Wringer"] }
    }.each do |rollout_mode, expected|
      website, webpage, source, statement = rollout_fixture_for(mode: expected[:mode], suffix: rollout_mode)
      expected_links = active_cache_links_for(website.seedurl, website: website)

      assert_cache_link_contract(
        expected_links,
        expected_rollout: rollout_mode,
        expected_active_backend: expected[:active_backend],
        expected_secondary_labels: expected[:secondary_labels],
        expected_url: website.seedurl
      )
      assert_equal shared_contract(expected_links), shared_contract(website_cache_links(website))
      assert_equal shared_contract(expected_links), shared_contract(webpage_cache_links(webpage))
      assert_equal shared_contract(expected_links), shared_contract(statement_cache_links(statement))
      assert_equal shared_contract(expected_links), shared_contract(source_cache_links(source))

      @statement = statement
      operator_links = operator_context_payload[:cache_links]
      assert_equal shared_contract(expected_links), shared_contract(operator_links)
      remove_instance_variable(:@statement)
    end
  end

  private

  def rollout_fixture_for(mode:, suffix:)
    website = Website.create!(
      name: "cache-link-#{suffix}",
      seedurl: "http://example.org/#{suffix}",
      graph_name: "http://example.com/cache-link-#{suffix}",
      default_language: "en",
      distillator_mode: mode
    )
    webpage = Webpage.create!(
      url: website.seedurl,
      language: "en",
      rdf_uri: "rdf:cache-link-#{suffix}",
      rdfs_class: rdfs_classes(:one),
      website: website
    )
    source = Source.create!(
      algorithm_value: "xpath=//title/text()",
      selected: true,
      selected_by: "Distillator",
      language: "en",
      render_js: false,
      property: properties(:one),
      website: website
    )
    statement = Statement.create!(
      cache: "cache-link-#{suffix}",
      source: source,
      webpage: webpage,
      status: "ok",
      status_origin: "condenser_refresh"
    )

    [website, webpage, source, statement]
  end

  def assert_cache_link_contract(links, expected_rollout:, expected_active_backend:, expected_secondary_labels:, expected_url:)
    assert_equal expected_rollout, links[:rollout_mode]
    assert_equal expected_active_backend, links[:active_backend]
    assert_equal "/condenser/cache/compare?uri=#{CGI.escape(expected_url)}", links[:compare_url]
    assert_equal expected_secondary_labels, Array(links[:secondary_links]).map { |link| link[:label] }
    assert links[:active_cache_url].present?
  end

  def shared_contract(links)
    links.slice(:active_cache_url, :rollout_mode, :active_backend, :compare_url).merge(
      secondary_labels: Array(links[:secondary_links]).map { |link| link[:label] }
    )
  end
end
