require 'test_helper'

class WebpagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @webpage = webpages(:one)
  end

  def create_test_website_with_webpage(distillator_mode:, seedurl:, url:)
    website = Website.create!(
      name: "cache link #{seedurl}",
      seedurl: seedurl,
      graph_name: "http://example.com/#{seedurl}",
      default_language: "en",
      distillator_mode: distillator_mode
    )

    webpage = Webpage.create!(
      url: url,
      language: "en",
      rdf_uri: "rdf:#{seedurl}",
      rdfs_class: rdfs_classes(:one),
      website: website,
      archive_date: Time.zone.parse("2026-01-01 12:00:00")
    )

    [website, webpage]
  end

  test "should get index" do
    get webpages_url
    assert_response :success
  end

  test "webpages json index preserves existing contract" do
    get webpages_url(format: :json)

    assert_response :success
    payload = JSON.parse(@response.body)
    assert payload.is_a?(Array)
    assert_includes payload.first.keys, "url"
    assert_includes payload.first.keys, "rdf_uri"
    assert_includes payload.first.keys, "publishable"
  end

  test "webpages index renders harmonized table shell and filters" do
    get webpages_url

    assert_response :success
    assert_harmonized_table_shell
    assert_select ".harmonized-table-filters", 1
    assert_harmonized_filter_form(action: "/webpages")
    assert_harmonized_apply_filters_button
    assert_select 'a', text: "Reset filters"
  end

  test "webpages index renders sortable headers" do
    get webpages_url

    assert_response :success
    assert_select 'th a[href*="sort=url"]'
    assert_select 'th a[href*="sort=language"]'
    assert_select 'th a[href*="sort=updated_at"]'
  end

  test "webpages index preserves active filters in sort links" do
    get webpages_url, params: { term: "example", language: "en", archive_state: "active", per_page: "10" }

    assert_response :success
    assert_sort_link_preserves_params(
      label: "Url",
      sort_key: "url",
      params: {
        term: "example",
        language: "en",
        archive_state: "active",
        per_page: "10"
      }
    )
  end

  test "webpages index filters through controller params using webpages index query" do
    matching = Webpage.create!(
      url: "http://example.com/query-match",
      language: "fr",
      rdf_uri: "rdf:query-match",
      rdfs_class: rdfs_classes(:one),
      website: websites(:one),
      archive_date: 1.day.ago
    )
    non_matching = Webpage.create!(
      url: "http://example.com/query-miss",
      language: "en",
      rdf_uri: "rdf:query-miss",
      rdfs_class: rdfs_classes(:place),
      website: websites(:two),
      archive_date: 5.days.from_now
    )

    get webpages_url, params: { term: "query-", language: "fr", archive_state: "archived" }

    assert_response :success
    assert_includes @response.body, matching.url
    assert_not_includes @response.body, non_matching.url
  end

  test "webpages index falls back safely for invalid sort and direction" do
    get webpages_url, params: { sort: "bogus", direction: "sideways" }

    assert_response :redirect
    assert_redirected_to "/webpages"
  end

  test "webpages index renders empty state" do
    get webpages_url, params: { term: "no-such-webpage-filter" }

    follow_redirect! if response.redirect?
    assert_response :success
    assert_select ".harmonized-table-empty-state", 1
  end

  test "should get new" do
    get new_webpage_url
    assert_response :success
  end

  test "should create webpage" do
    assert_difference('Webpage.count') do
      post webpages_url, params: { webpage: { language: @webpage.language, rdf_uri: @webpage.rdf_uri, rdfs_class_id: @webpage.rdfs_class_id, url: @webpage.url + "newwebpageurl", website_id: @webpage.website_id } }
    end

    assert_redirected_to webpage_url(Webpage.last)
  end

  test "should show webpage" do
    assert_read_only_page_does_not_fetch
    get webpage_url(@webpage)
    assert_response :success
  end

  test "website show uses cache link resolver labels for legacy mode" do
    assert_read_only_page_does_not_fetch
    @webpage.website.update!(distillator_mode: "legacy")

    get webpage_url(@webpage)

    assert_response :success
    assert_includes @response.body, "Open active cache"
    assert_includes @response.body, "Open Condenser cache"
    assert_includes @response.body, "Active backend:</strong> Wringer"
  end

  test "webpage show uses cache link resolver labels for shadow mode" do
    assert_read_only_page_does_not_fetch
    @webpage.website.update!(distillator_mode: "shadow")

    get webpage_url(@webpage)

    assert_response :success
    assert_includes @response.body, "Open active cache"
    assert_includes @response.body, "Compare Condenser vs Wringer"
    assert_includes @response.body, "Active backend:</strong> Wringer"
  end

  test "webpage show uses cache link resolver labels for active mode" do
    assert_read_only_page_does_not_fetch
    @webpage.website.update!(distillator_mode: "active")

    get webpage_url(@webpage)

    assert_response :success
    assert_includes @response.body, "Open active cache"
    assert_includes @response.body, "Inspect legacy Wringer"
    assert_includes @response.body, "Active backend:</strong> Condenser"
  end

  test "webpage rollout panel uses centralized operator copy and avoids retired wording" do
    assert_read_only_page_does_not_fetch
    @webpage.website.update!(distillator_mode: "shadow")

    get webpage_url(@webpage)

    assert_response :success
    assert_includes @response.body, Distillator::RolloutCopy.rollout_panel_title
    assert_includes @response.body, Distillator::RolloutCopy.label(:shadow)
    assert_includes @response.body, Distillator::RolloutCopy.description(:shadow)
    assert_not_includes @response.body, "Distillator rollout"
    assert_not_includes @response.body, "internal"
    assert_not_includes @response.body, "new cache"
    assert_not_includes @response.body, "phase I"
    assert_not_includes @response.body, "preview only"
  end

  test "webpage show does not fetch" do
    assert_read_only_page_does_not_fetch

    get webpage_url(@webpage)

    assert_response :success
  end

  test "webpage pages render cache links without fetching" do
    assert_read_only_page_does_not_fetch
    website, webpage = create_test_website_with_webpage(
      distillator_mode: "active",
      seedurl: "active-cache-index",
      url: "http://example.com/active-cache-index"
    )

    get webpages_url, params: { seedurl: website.seedurl }
    assert_response :success
    assert_includes @response.body, "<th>Active Cache</th>"
    assert_not_includes @response.body, "<th>Condenser Cache</th>"
    assert_includes @response.body, "Open active cache"
    assert_not_includes @response.body, "Open Condenser cache"
    assert_includes @response.body, "Condenser active"
    assert_includes @response.body, "Active: Condenser"
    assert_includes @response.body, "/condenser/cache?term=#{CGI.escape(webpage.url)}"

    get webpage_url(webpage)
    assert_response :success
    assert_select 'details[data-operator-context-card]'
    assert_select 'details[data-context-domain="status"]'
    assert_select 'details[data-context-domain="actions"]'
    assert_select 'details[data-context-domain="details"]'
    assert_includes @response.body, "Condenser active"
    assert_includes @response.body, "Condenser serves fetch/cache results; legacy Wringer remains available for inspection."
    assert_includes @response.body, "Active: Condenser"
    assert_includes @response.body, "Inspect legacy Wringer"
    assert_includes @response.body, "Diagnose refresh"
  end

  test "webpage show renders rollout warning for shadow website" do
    assert_read_only_page_does_not_fetch
    @webpage.website.update!(distillator_mode: "shadow")

    get webpage_url(@webpage)

    assert_response :success
    assert_includes @response.body, "Shadow comparison"
    assert_includes @response.body, "Wringer serves production results; Condenser compares in the background."
    assert_includes @response.body, "Active: Wringer + Shadow comparison"
    assert_includes @response.body, "Compare Condenser vs Wringer"
  end

  test "webpage index shows distillator cache column when wringer remains active" do
    Distillator::FetchCacheStore.expects(:fetch).never
    website, webpage = create_test_website_with_webpage(
      distillator_mode: "legacy",
      seedurl: "legacy-cache-index",
      url: "http://example.com/legacy-cache-index"
    )

    get webpages_url, params: { seedurl: website.seedurl }

    assert_response :success
    assert_includes @response.body, "<th>Active Cache</th>"
    assert_includes @response.body, "<th>Condenser Cache</th>"
    assert_includes @response.body, "Open active cache"
    assert_includes @response.body, "Open Condenser cache"
    assert_includes @response.body, "Active: Wringer"
    assert_includes @response.body, "/condenser/cache?term=#{CGI.escape(webpage.url)}"
    assert_not_includes @response.body, "/condenser/cache?term=#{CGI.escape(website.seedurl)}"
  end

  test "webpage index hides distillator cache column when active cache is already distillator" do
    Distillator::FetchCacheStore.expects(:fetch).never
    website, webpage = create_test_website_with_webpage(
      distillator_mode: "active",
      seedurl: "active-column-hidden",
      url: "http://example.com/active-column-hidden"
    )

    get webpages_url, params: { seedurl: website.seedurl }

    assert_response :success
    assert_includes @response.body, "<th>Active Cache</th>"
    assert_not_includes @response.body, "<th>Condenser Cache</th>"
    assert_includes @response.body, "Open active cache"
    assert_not_includes @response.body, "Open Condenser cache"
    assert_includes @response.body, "Active: Condenser"
    assert_includes @response.body, "/condenser/cache?term=#{CGI.escape(webpage.url)}"
  end

  test "webpage index shows distillator cache column when shadow mode exposes that link" do
    Distillator::FetchCacheStore.expects(:fetch).never
    website, webpage = create_test_website_with_webpage(
      distillator_mode: "shadow",
      seedurl: "shadow-column-hidden",
      url: "http://example.com/shadow-column-hidden"
    )

    get webpages_url, params: { seedurl: website.seedurl }

    assert_response :success
    assert_includes @response.body, "<th>Active Cache</th>"
    assert_includes @response.body, "<th>Condenser Cache</th>"
    assert_includes @response.body, "Open active cache"
    assert_includes @response.body, "Open Condenser cache"
    assert_includes @response.body, "Active: Wringer + Shadow comparison"
    assert_includes @response.body, "/condenser/cache?term=#{CGI.escape(webpage.url)}"
  end

  test "should get edit" do
    get edit_webpage_url(@webpage)
    assert_response :success
  end

  test "should update webpage" do
    patch webpage_url(@webpage), params: { webpage: { language: @webpage.language, rdf_uri: @webpage.rdf_uri, rdfs_class_id: @webpage.rdfs_class_id, url: @webpage.url, website_id: @webpage.website_id } }
    assert_redirected_to webpage_url(@webpage)
  end

  test "should destroy webpage" do
    assert_difference('Webpage.count', -1) do
      delete webpage_url(@webpage)
    end

    assert_redirected_to webpages_url
  end

  private

  def assert_read_only_page_does_not_fetch
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never
  end
end
