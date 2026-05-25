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

  test "webpages index drops ignored publishable false and page params from canonical urls" do
    website, = build_transition_inspection_website(seedurl: "canonical-webpages-site")

    get webpages_url, params: {
      seedurl: website.seedurl,
      publishable: "false",
      page: "2",
      per_page: "1"
    }

    assert_response :redirect
    assert_redirected_to webpages_path(seedurl: website.seedurl)
  end

  test "webpages index defaults to active publishable event webpages for selected website" do
    website, active_publishable, archived_publishable, active_unpublishable, place_page = build_transition_inspection_website(seedurl: "default-scope-site")

    get webpages_url, params: { seedurl: website.seedurl }

    assert_response :success
    assert_includes @response.body, active_publishable.url
    assert_not_includes @response.body, archived_publishable.url
    assert_not_includes @response.body, active_unpublishable.url
    assert_not_includes @response.body, place_page.url
    assert_includes @response.body, "Showing 1 publishable event page for this website."
    assert_match(%r{href="/webpages\?(?:scope=all&amp;seedurl=#{website.seedurl}|seedurl=#{website.seedurl}&amp;scope=all)">Show all webpages}, @response.body)
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
    assert_match(%r{href="/webpages\?seedurl=#{website.seedurl}">Show publishable event pages}, @response.body)
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

  test "webpages index renders empty state" do
    get webpages_url, params: { term: "no-such-webpage-filter" }

    follow_redirect! if response.redirect?
    assert_response :success
    assert_select ".harmonized-table-empty-state", 1
  end

  test "webpages index shows website scoped summary and navigation" do
    website = Website.create!(
      name: "Scoped summary website",
      seedurl: "scoped-summary-website",
      graph_name: "https://example.org/scoped-summary-website",
      default_language: "en"
    )

    publishable_page = Webpage.create!(url: "https://example.org/events/scoped", language: "en", rdf_uri: "rdf:scoped:event", rdfs_class: rdfs_classes(:one), website: website)
    create_publishable_statements_for(publishable_page)
    Webpage.create!(url: "footlight:scoped:person", language: "en", rdf_uri: "rdf:scoped:person", rdfs_class: rdfs_classes(:person), website: website)

    get webpages_url, params: { seedurl: website.seedurl, scope: "all" }

    assert_response :success
    assert_includes @response.body, "Showing 2 matching webpages."
    assert_match(%r{href="/webpages\?(?:scope=all&amp;seedurl=#{website.seedurl}|seedurl=#{website.seedurl}&amp;scope=all)"}, @response.body)
    assert_match(%r{href="/webpages\?seedurl=#{website.seedurl}">Show publishable event pages}, @response.body)
    assert_select "a[href='#{website_path(website)}']", text: website.name
    assert_select "a[href='/webpages?seedurl=#{website.seedurl}']", text: "webpages"
    assert_select "a[href='/sources?seedurl=#{website.seedurl}']", text: "sources"
    assert_select "a[href='/statements?seedurl=#{website.seedurl}']", text: "statements"
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

  test "webpage pages render representative cache links without fetching" do
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
