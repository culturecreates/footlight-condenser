require 'test_helper'

class WebpagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @webpage = webpages(:one)
    Distillator::WringerEndpoint.stubs(:current).returns(
      Distillator::WringerEndpoint::Result.new(
        compatibility_base_url: "http://compat.example",
        legacy_lookup_base_url: "http://wringer.example",
        compatibility_source: "DISTILLATOR_COMPAT_BASE_URL",
        state: :remote_configured,
        status_label: "Current Wringer: Remote configured",
        status_detail: "http://compat.example via DISTILLATOR_COMPAT_BASE_URL"
      )
    )
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

  def build_transition_inspection_website(seedurl: "transition-inspection-site")
    website = Website.create!(
      name: "Transition inspection #{seedurl}",
      seedurl: seedurl,
      graph_name: "http://example.com/#{seedurl}",
      default_language: "en"
    )

    active_publishable = Webpage.create!(
      url: "https://example.org/#{seedurl}/active-publishable",
      language: "en",
      rdf_uri: "rdf:#{seedurl}:active-publishable",
      rdfs_class: rdfs_classes(:one),
      website: website,
      archive_date: 3.days.from_now
    )
    create_publishable_statements_for(active_publishable)

    archived_publishable = Webpage.create!(
      url: "https://example.org/#{seedurl}/archived-publishable",
      language: "en",
      rdf_uri: "rdf:#{seedurl}:archived-publishable",
      rdfs_class: rdfs_classes(:one),
      website: website,
      archive_date: 2.days.ago
    )
    create_publishable_statements_for(archived_publishable)

    active_unpublishable = Webpage.create!(
      url: "https://example.org/#{seedurl}/active-unpublishable",
      language: "en",
      rdf_uri: "rdf:#{seedurl}:active-unpublishable",
      rdfs_class: rdfs_classes(:one),
      website: website,
      archive_date: 5.days.from_now
    )

    place_page = Webpage.create!(
      url: "https://example.org/#{seedurl}/place-page",
      language: "en",
      rdf_uri: "rdf:#{seedurl}:place-page",
      rdfs_class: rdfs_classes(:place),
      website: website,
      archive_date: 5.days.from_now
    )

    [website, active_publishable, archived_publishable, active_unpublishable, place_page]
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
    get webpages_url, params: {
      seedurl: websites(:one).seedurl,
      scope: "all",
      term: "example",
      language: "en",
      archive_state: "active",
      url_kind: "public",
      rdfs_class: "Event",
      publishable: "true",
      page: "2"
    }

    follow_redirect! if response.redirect?
    assert_response :success
    assert_sort_link_preserves_filters(
      label: "Url",
      sort_key: "url",
      params: {
        seedurl: websites(:one).seedurl,
        scope: "all",
        term: "example",
        language: "en",
        archive_state: "active",
        url_kind: "public",
        rdfs_class: "Event",
        publishable: "true"
      }
    )
  end

  test "webpages index canonicalizes scope all publishable false and drops page params" do
    website, = build_transition_inspection_website(seedurl: "canonical-webpages-site")

    get webpages_url, params: {
      seedurl: website.seedurl,
      publishable: "false",
      page: "2",
      per_page: "1"
    }

    assert_response :redirect
    assert_redirected_to webpages_path(seedurl: website.seedurl, scope: "all", publishable: "false")
  end

  test "webpages index defaults to active publishable event webpages for selected website" do
    website, active_publishable, archived_publishable, active_unpublishable, place_page = build_transition_inspection_website(seedurl: "default-scope-site")

    get webpages_url, params: { seedurl: website.seedurl }

    assert_response :success
    assert_includes @response.body, active_publishable.url
    assert_not_includes @response.body, archived_publishable.url
    assert_not_includes @response.body, active_unpublishable.url
    assert_not_includes @response.body, place_page.url
    assert_includes @response.body, "Showing 1 active publishable event pages for this website."
    assert_select "a[href='#{webpages_path(seedurl: website.seedurl, scope: "all")}']", text: "Show all webpages"
    assert_select "a[href='#{webpage_path(active_publishable, return_to: webpages_path(seedurl: website.seedurl))}']", text: "Show"
  end

  test "webpages index scope all shows all webpages for selected website" do
    website, active_publishable, archived_publishable, active_unpublishable, place_page = build_transition_inspection_website(seedurl: "all-scope-site")

    get webpages_url, params: { seedurl: website.seedurl, scope: "all" }

    assert_response :success
    assert_includes @response.body, active_publishable.url
    assert_includes @response.body, archived_publishable.url
    assert_includes @response.body, active_unpublishable.url
    assert_includes @response.body, place_page.url
    assert_includes @response.body, "Showing 4 matching webpages."
    assert_select "input[name='scope'][value='all']", 1
    assert_select "a[href='#{webpages_path(seedurl: website.seedurl)}']", text: "Show publishable event pages"
  end

  test "webpages index scope all publishable false shows only non publishable webpages" do
    website, active_publishable, archived_publishable, active_unpublishable, place_page = build_transition_inspection_website(seedurl: "all-scope-unpublishable-site")

    get webpages_url, params: { seedurl: website.seedurl, scope: "all", publishable: "false" }

    assert_response :success
    assert_not_includes @response.body, active_publishable.url
    assert_not_includes @response.body, archived_publishable.url
    assert_includes @response.body, active_unpublishable.url
    assert_includes @response.body, place_page.url
  end

  test "webpages index ignores page and per page for rendering and pagination controls" do
    website, active_publishable, = build_transition_inspection_website(seedurl: "no-pagination-site")
    extra_pages = 30.times.map do |index|
      webpage = Webpage.create!(
        url: "https://example.org/no-pagination-site/more-#{index}",
        language: "en",
        rdf_uri: "rdf:no-pagination-site:#{index}",
        rdfs_class: rdfs_classes(:one),
        website: website,
        archive_date: 5.days.from_now
      )
      create_publishable_statements_for(webpage)
      webpage
    end

    get webpages_url, params: { seedurl: website.seedurl, page: "2", per_page: "1" }
    assert_response :redirect
    follow_redirect!

    assert_response :success
    assert_includes @response.body, active_publishable.url
    extra_pages.each do |webpage|
      assert_includes @response.body, webpage.url
    end
    assert_select "input[name='per_page']", 0
    assert_select "a", text: "Previous page", count: 0
    assert_select "a", text: "Next page", count: 0
    assert_no_match(/Showing page \d+ of \d+\./, @response.body)
  end

  test "webpages index filters through controller params using webpages index query" do
    matching = Webpage.create!(
      url: "http://example.com/query-match",
      language: "fr",
      rdf_uri: "rdf:query-match",
      rdfs_class: rdfs_classes(:one),
      website: websites(:one),
      archive_date: 5.days.from_now
    )
    create_publishable_statements_for(matching)
    non_matching = Webpage.create!(
      url: "http://example.com/query-miss",
      language: "en",
      rdf_uri: "rdf:query-miss",
      rdfs_class: rdfs_classes(:place),
      website: websites(:two),
      archive_date: 5.days.from_now
    )

    get webpages_url, params: { term: "query-", language: "fr" }

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

  test "webpages index shows website scoped typed summary and preserves reset seedurl" do
    website = Website.create!(
      name: "Typed summary website",
      seedurl: "typed-summary-website",
      graph_name: "https://example.org/typed-summary-website",
      default_language: "en"
    )

    resource_list_class = RdfsClass.create!(name: "ResourceList")
    web_page_class = RdfsClass.create!(name: "WebPage")
    other_class = RdfsClass.create!(name: "Thingish")

    publishable_page = Webpage.create!(url: "https://example.org/events/typed", language: "en", rdf_uri: "rdf:typed:event", rdfs_class: rdfs_classes(:one), website: website)
    create_publishable_statements_for(publishable_page)
    Webpage.create!(url: "https://example.org/events/blocked", language: "en", rdf_uri: "rdf:typed:event:blocked", rdfs_class: rdfs_classes(:one), website: website)
    Webpage.create!(url: "footlight:typed:person", language: "en", rdf_uri: "rdf:typed:person", rdfs_class: rdfs_classes(:person), website: website)
    Webpage.create!(url: "footlight:typed:place", language: "en", rdf_uri: "rdf:typed:place", rdfs_class: rdfs_classes(:place), website: website)
    Webpage.create!(url: "https://example.org/resources/typed", language: "en", rdf_uri: "rdf:typed:resource-list", rdfs_class: resource_list_class, website: website)
    Webpage.create!(url: "https://example.org/pages/typed", language: "en", rdf_uri: "rdf:typed:webpage", rdfs_class: web_page_class, website: website)
    Webpage.create!(url: "footlight:typed:other", language: "en", rdf_uri: "rdf:typed:other", rdfs_class: other_class, website: website)

    get webpages_url, params: { seedurl: website.seedurl, scope: "all" }

    assert_response :success
    assert_includes @response.body, "Showing 7 matching webpages."
    assert_includes @response.body, "4 public source URLs · 3 internal entity URIs"
    assert_includes @response.body, "Events 2 · People 1 · Places 1 · Resource lists 1 · Web pages 1 · Other 1"
    assert_includes @response.body, "Publishable 1 · Not publishable 6"
    assert_match(%r{href="/webpages\?(?:scope=all&amp;seedurl=#{website.seedurl}|seedurl=#{website.seedurl}&amp;scope=all)"}, @response.body)
    assert_select "a[href='/webpages?seedurl=#{website.seedurl}']", text: "Show publishable event pages"
    assert_select "a[href='#{website_path(website)}']", text: website.name
    assert_select "a[href='/webpages?seedurl=#{website.seedurl}']", text: "webpages"
    assert_select "a[href='/sources?seedurl=#{website.seedurl}']", text: "sources"
    assert_select "a[href='/statements?seedurl=#{website.seedurl}']", text: "statements"
  end

  test "webpages index filtered summary keeps website total semantics" do
    website = Website.create!(
      name: "Filtered summary website",
      seedurl: "filtered-summary-website",
      graph_name: "https://example.org/filtered-summary-website",
      default_language: "en"
    )

    publishable_page = Webpage.create!(url: "https://example.org/events/filtered", language: "en", rdf_uri: "rdf:filtered:event", rdfs_class: rdfs_classes(:one), website: website)
    create_publishable_statements_for(publishable_page)
    Webpage.create!(url: "footlight:filtered:other", language: "en", rdf_uri: "rdf:filtered:other", rdfs_class: rdfs_classes(:person), website: website)

    get webpages_url, params: { seedurl: website.seedurl, scope: "all", publishable: "true" }

    assert_response :success
    assert_includes @response.body, "Showing 1 matching webpages."
    assert_includes @response.body, "Total website webpages: 2."
  end

  test "global webpages index keeps global navigation without seedurl context" do
    get webpages_url

    assert_response :success
    assert_select "a[href='#{webpages_path}']", text: "webpages"
    assert_select "a[href='#{sources_path}']", text: "sources"
    assert_select "a[href='#{statements_path}']", text: "statements"
  end

  test "should get new" do
    get new_webpage_url
    assert_response :success
  end

  test "should create webpage" do
    assert_difference('Webpage.count') do
      post webpages_url, params: {
        return_to: "/webpages?seedurl=#{@webpage.website.seedurl}&scope=all",
        webpage: { language: @webpage.language, rdf_uri: @webpage.rdf_uri, rdfs_class_id: @webpage.rdfs_class_id, url: @webpage.url + "newwebpageurl", website_id: @webpage.website_id }
      }
    end

    assert_redirected_to "/webpages?seedurl=#{@webpage.website.seedurl}&scope=all"
  end

  test "should show webpage" do
    assert_read_only_page_does_not_fetch
    get webpage_url(@webpage)
    assert_response :success
    assert_select 'details[data-operator-context-card]', 0
    assert_includes @response.body, "Production transition"
    assert_includes @response.body, "Data actions"
    assert_includes @response.body, "JSON-LD"
    assert_includes @response.body, "Validation"
    assert_includes @response.body, "Page actions"
  end

  test "webpage show preserves safe return to links" do
    return_to = "/webpages?seedurl=#{@webpage.website.seedurl}&scope=all"

    get webpage_url(@webpage, return_to: return_to)

    assert_response :success
    assert_select "a[href='#{edit_webpage_path(@webpage, return_to: return_to)}']", text: "Edit"
    assert_match(%r{href="/webpages\?(?:seedurl=#{@webpage.website.seedurl}&amp;scope=all|scope=all&amp;seedurl=#{@webpage.website.seedurl})"}, @response.body)
  end

  test "website show uses cache link resolver labels for legacy mode" do
    assert_read_only_page_does_not_fetch
    @webpage.website.update!(distillator_mode: "legacy")

    get webpage_url(@webpage)

    assert_response :success
    assert_includes @response.body, "Open active cache"
    assert_includes @response.body, "Open Condenser cache"
    assert_includes @response.body, "Production backend:</strong> Wringer"
  end

  test "webpage show uses cache link resolver labels for shadow mode" do
    assert_read_only_page_does_not_fetch
    @webpage.website.update!(distillator_mode: "shadow")

    get webpage_url(@webpage)

    assert_response :success
    assert_includes @response.body, "Open active cache"
    assert_includes @response.body, "Compare Condenser vs Wringer"
    assert_includes @response.body, "Production backend:</strong> Wringer"
  end

  test "webpage show uses cache link resolver labels for active mode" do
    assert_read_only_page_does_not_fetch
    @webpage.website.update!(distillator_mode: "active")

    get webpage_url(@webpage)

    assert_response :success
    assert_includes @response.body, "Open active cache"
    assert_includes @response.body, "Inspect legacy Wringer"
    assert_includes @response.body, "Production backend:</strong> Condenser"
  end

  test "webpage show uses one production transition section and avoids retired wording" do
    assert_read_only_page_does_not_fetch
    @webpage.website.update!(distillator_mode: "shadow")

    get webpage_url(@webpage)

    assert_response :success
    assert_includes @response.body, "Production transition"
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

    get webpages_url, params: { seedurl: website.seedurl, scope: "all" }
    assert_response :success
    assert_includes @response.body, "<th>Active Cache</th>"
    assert_not_includes @response.body, "<th>Condenser Cache</th>"
    assert_includes @response.body, "Open active cache"
    assert_not_includes @response.body, "Open Condenser cache"
    assert_includes @response.body, "Active"
    assert_includes @response.body, "Production: Condenser"
    assert_includes @response.body, "/condenser/cache?term=#{CGI.escape(webpage.url)}"

    get webpage_url(webpage)
    assert_response :success
    assert_select 'details[data-operator-context-card]', 0
    assert_includes @response.body, "Active"
    assert_includes @response.body, "Production backend:</strong> Condenser"
    assert_includes @response.body, "Inspect legacy Wringer"
    assert_includes @response.body, "Diagnose refresh"
  end

  test "webpage show renders rollout warning for shadow website" do
    assert_read_only_page_does_not_fetch
    @webpage.website.update!(distillator_mode: "shadow")

    get webpage_url(@webpage)

    assert_response :success
    assert_includes @response.body, "Shadow"
    assert_includes @response.body, "Wringer serves production while Condenser is checked in the background."
    assert_includes @response.body, "Production backend:</strong> Wringer"
    assert_includes @response.body, "Compare Condenser vs Wringer"
  end

  test "webpage show keeps rollout copy compact and grouped links visible" do
    assert_read_only_page_does_not_fetch
    @webpage.website.update!(distillator_mode: "legacy")

    get webpage_url(@webpage)

    assert_response :success
    assert_operator @response.body.scan("Legacy").length, :>=, 1
    assert_operator @response.body.scan("Wringer serves production.").length, :<=, 2
    assert_includes @response.body, "Statements"
    assert_includes @response.body, "Refresh"
    assert_includes @response.body, "Google JSON-LD"
    assert_includes @response.body, "Artsdata JSON-LD"
    assert_includes @response.body, "Call Condenser"
    assert_includes @response.body, "Code Snippet API"
    assert_includes @response.body, "Edit"
    assert_includes @response.body, "Back"
  end

  test "webpage show uses diagnostic next step for invalid cache urls" do
    assert_read_only_page_does_not_fetch
    website, webpage = create_test_website_with_webpage(
      distillator_mode: "legacy",
      seedurl: "footlight-invalid-cache",
      url: "footlight:test-id"
    )

    get webpage_url(webpage)

    assert_response :success
    assert_includes @response.body, "Invalid cache URL"
    assert_operator @response.body.scan("Invalid cache URL").length, :<=, 1
    assert_includes @response.body, "Use Diagnose refresh to inspect why this URL is not cache-inspectable."
    assert_not_includes @response.body, "Inspect Condenser cache before promotion"
    assert_includes @response.body, "Diagnose refresh"
  end

  test "webpage index shows distillator cache column when wringer remains active" do
    Distillator::FetchCacheStore.expects(:fetch).never
    website, webpage = create_test_website_with_webpage(
      distillator_mode: "legacy",
      seedurl: "legacy-cache-index",
      url: "http://example.com/legacy-cache-index"
    )

    get webpages_url, params: { seedurl: website.seedurl, scope: "all" }

    assert_response :success
    assert_includes @response.body, "<th>Active Cache</th>"
    assert_not_includes @response.body, "<th>Condenser Cache</th>"
    assert_includes @response.body, "Open active cache"
    assert_not_includes @response.body, "Open Condenser cache"
    assert_includes @response.body, "Production: Wringer"
    assert_not_includes @response.body, "/condenser/cache?term=#{CGI.escape(webpage.url)}"
    assert_not_includes @response.body, "/condenser/cache?term=#{CGI.escape(website.seedurl)}"
  end

  test "webpage index hides distillator cache column when active cache is already distillator" do
    Distillator::FetchCacheStore.expects(:fetch).never
    website, webpage = create_test_website_with_webpage(
      distillator_mode: "active",
      seedurl: "active-column-hidden",
      url: "http://example.com/active-column-hidden"
    )

    get webpages_url, params: { seedurl: website.seedurl, scope: "all" }

    assert_response :success
    assert_includes @response.body, "<th>Active Cache</th>"
    assert_not_includes @response.body, "<th>Condenser Cache</th>"
    assert_includes @response.body, "Open active cache"
    assert_not_includes @response.body, "Open Condenser cache"
    assert_includes @response.body, "Production: Condenser"
    assert_includes @response.body, "/condenser/cache?term=#{CGI.escape(webpage.url)}"
  end

  test "webpage index shows distillator cache column when shadow mode exposes that link" do
    Distillator::FetchCacheStore.expects(:fetch).never
    website, webpage = create_test_website_with_webpage(
      distillator_mode: "shadow",
      seedurl: "shadow-column-hidden",
      url: "http://example.com/shadow-column-hidden"
    )

    get webpages_url, params: { seedurl: website.seedurl, scope: "all" }

    assert_response :success
    assert_includes @response.body, "<th>Active Cache</th>"
    assert_not_includes @response.body, "<th>Condenser Cache</th>"
    assert_includes @response.body, "Open active cache"
    assert_not_includes @response.body, "Open Condenser cache"
    assert_includes @response.body, "Production: Wringer"
    assert_not_includes @response.body, "/condenser/cache?term=#{CGI.escape(webpage.url)}"
  end

  test "should get edit" do
    get edit_webpage_url(@webpage)
    assert_response :success
  end

  test "should update webpage" do
    patch webpage_url(@webpage), params: {
      return_to: "/webpages?seedurl=#{@webpage.website.seedurl}",
      webpage: { language: @webpage.language, rdf_uri: @webpage.rdf_uri, rdfs_class_id: @webpage.rdfs_class_id, url: @webpage.url, website_id: @webpage.website_id }
    }
    assert_redirected_to "/webpages?seedurl=#{@webpage.website.seedurl}"
  end

  test "should destroy webpage" do
    assert_difference('Webpage.count', -1) do
      delete webpage_url(@webpage), params: { return_to: "/webpages?seedurl=#{@webpage.website.seedurl}&scope=all" }
    end

    assert_redirected_to "/webpages?seedurl=#{@webpage.website.seedurl}&scope=all"
  end

  test "unsafe return to falls back to a safe webpages path" do
    patch webpage_url(@webpage), params: {
      return_to: "https://evil.example/webpages",
      webpage: { language: @webpage.language, rdf_uri: @webpage.rdf_uri, rdfs_class_id: @webpage.rdfs_class_id, url: @webpage.url, website_id: @webpage.website_id }
    }

    assert_redirected_to webpage_url(@webpage)
  end

  private

  def create_publishable_statements_for(webpage)
    [
      [properties(:four), "Publishable title"],
      [properties(:location), '[["Salle","uri:place"]]'],
      [properties(:six), '["2026-06-01T20:00:00-04:00"]']
    ].each do |property, cache|
      source = Source.create!(
        website: webpage.website,
        property: property,
        language: "en",
        selected: true,
        algorithm_value: "controller-test"
      )

      Statement.create!(
        webpage: webpage,
        source: source,
        cache: cache,
        status: "ok"
      )
      Statement.where(webpage: webpage, source: source).update_all(status: "ok")
    end
  end

  def assert_read_only_page_does_not_fetch
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never
  end
end
