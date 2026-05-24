require 'test_helper'

class WebsitesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @website = websites(:one)
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    @old_override_flag = ENV["DISTILLATOR_ALLOW_ACTIVE_OVERRIDE"]
    @old_heroku_app_name = ENV["HEROKU_APP_NAME"]
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

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
    ENV["DISTILLATOR_ALLOW_ACTIVE_OVERRIDE"] = @old_override_flag
    ENV["HEROKU_APP_NAME"] = @old_heroku_app_name
  end

  test "should get index" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "legacy")

    get websites_url

    assert_response :success
    assert_harmonized_table_shell
    assert_harmonized_filter_form(action: "/websites")
    assert_harmonized_apply_filters_button
    assert_harmonized_reset_filters_link(path: "/websites")
    assert_includes @response.body, "Legacy:"
    assert_includes @response.body, "Shadow:"
    assert_includes @response.body, "Active:"
    assert_includes @response.body, "Unknown:"
    assert_includes @response.body, "La Vitrine pipeline"
    assert_includes @response.body, "Website rollout filters"
    assert_select 'details[data-operator-context-card]', 0
    assert_no_cohort_source_requests
  end

  test "websites index renders typed webpage summary cell with scoped links" do
    website = Website.create!(
      name: "Typed dashboard website",
      seedurl: "typed-dashboard-website",
      graph_name: "https://example.org/typed-dashboard-website",
      default_language: "en"
    )

    resource_list_class = RdfsClass.create!(name: "ResourceList")
    web_page_class = RdfsClass.create!(name: "WebPage")
    other_class = RdfsClass.create!(name: "Thingish")

    publishable_page = Webpage.create!(url: "https://example.org/events/dashboard", language: "en", rdf_uri: "rdf:dashboard:event", rdfs_class: rdfs_classes(:one), website: website)
    create_publishable_statements_for(publishable_page)
    Webpage.create!(url: "https://example.org/events/dashboard-blocked", language: "en", rdf_uri: "rdf:dashboard:event:blocked", rdfs_class: rdfs_classes(:one), website: website)
    Webpage.create!(url: "footlight:dashboard:person", language: "en", rdf_uri: "rdf:dashboard:person", rdfs_class: rdfs_classes(:person), website: website)
    Webpage.create!(url: "footlight:dashboard:place", language: "en", rdf_uri: "rdf:dashboard:place", rdfs_class: rdfs_classes(:place), website: website)
    Webpage.create!(url: "https://example.org/resources/dashboard", language: "en", rdf_uri: "rdf:dashboard:resource-list", rdfs_class: resource_list_class, website: website)
    Webpage.create!(url: "https://example.org/pages/dashboard", language: "en", rdf_uri: "rdf:dashboard:webpage", rdfs_class: web_page_class, website: website)
    Webpage.create!(url: "footlight:dashboard:other", language: "en", rdf_uri: "rdf:dashboard:other", rdfs_class: other_class, website: website)

    get websites_url, params: { q: "Typed dashboard website" }

    assert_response :success
    assert_includes @response.body, "7 total"
    assert_includes @response.body, "4 public"
    assert_includes @response.body, "3 internal"
    assert_includes @response.body, "E2"
    assert_includes @response.body, "Pe1"
    assert_includes @response.body, "Pl1"
    assert_includes @response.body, "R1"
    assert_includes @response.body, "W1"
    assert_includes @response.body, "O1"
    assert_includes @response.body, "1 publishable"
    assert_includes @response.body, "6 not publishable"
    assert_match %r{/webpages\?(seedurl=#{website.seedurl}&amp;url_kind=public|url_kind=public&amp;seedurl=#{website.seedurl})}, @response.body
    assert_match %r{/webpages\?(seedurl=#{website.seedurl}&amp;rdfs_class=Event|rdfs_class=Event&amp;seedurl=#{website.seedurl})}, @response.body
    assert_match %r{/webpages\?(seedurl=#{website.seedurl}&amp;publishable=true|publishable=true&amp;seedurl=#{website.seedurl})}, @response.body
  end

  test "should get new" do
    get new_website_url
    assert_response :success
    assert_includes @response.body, 'name="website[distillator_mode]"'
    assert_includes @response.body, ">Legacy<"
    assert_includes @response.body, ">Shadow<"
    assert_includes @response.body, ">Active<"
    assert_includes @response.body, "Wringer serves production."
    assert_includes @response.body, "Wringer serves production while Condenser is checked in the background."
    assert_includes @response.body, "Condenser serves production while Wringer stays available for diagnostics."
    assert_not_includes @response.body, "new cache"
    assert_not_includes @response.body, ">internal<"
  end

  test "should create website" do
    assert_difference('Website.count') do
      post websites_url, params: { website: { name: @website.name, seedurl: @website.seedurl, distillator_mode: "shadow" } }
    end

    assert_redirected_to website_url(Website.last)
    assert_equal "shadow", Website.last.distillator_mode
  end

  test "should show website" do
    assert_read_only_page_does_not_fetch
    stub_remote_wringer_endpoint
    @website.update!(distillator_mode: "shadow")
    get website_url(@website)
    assert_response :success
    assert_select 'details[data-operator-context-card]', 0
    assert_includes @response.body, "Transition"
    assert_includes @response.body, "Current mode:"
    assert_includes @response.body, "Production backend:"
    assert_includes @response.body, "Next recommended action:"
    assert_includes @response.body, "Readiness:"
    assert_includes @response.body, "Latest rollout event:"
    assert_includes @response.body, "Shadow"
    assert_includes @response.body, "Wringer"
    assert_includes @response.body, "Run transition check"
    assert_includes @response.body, "Compare Condenser vs Wringer"
    assert_includes @response.body, "Operations"
    assert_includes @response.body, "Batch jobs"
    assert_includes @response.body, "Danger zone"
    assert_includes @response.body, "Edit"
    assert_not_includes @response.body, "Back"
    assert_not_includes @response.body, "/distillator/cache/preview?uri=#{CGI.escape(@website.seedurl)}"
    assert_no_cohort_source_requests
  end

  test "websites index shows la vitrine badge for cohort sites and not for non cohort sites" do
    cohort = Website.create!(
      name: "Hector Charland",
      seedurl: "hector-charland-com",
      graph_name: "http://example.com/tout-culture",
      default_language: "en",
      distillator_mode: "shadow"
    )
    non_cohort = Website.create!(
      name: "Outside Feed",
      seedurl: "outside-feed",
      graph_name: "http://example.com/outside-feed",
      default_language: "en",
      distillator_mode: "shadow"
    )

    get websites_url, params: { q: "Feed" }

    assert_response :success
    assert_includes @response.body, non_cohort.name
    assert_not_includes @response.body, cohort.name

    get websites_url, params: { q: "Hector" }

    assert_response :success
    assert_includes @response.body, cohort.name
    assert_includes @response.body, "La Vitrine pipeline"
    assert_no_cohort_source_requests
  end

  test "websites index filters by la vitrine cohort" do
    cohort = Website.create!(
      name: "Hector Charland",
      seedurl: "hector-charland-com",
      graph_name: "http://example.com/tout-culture",
      default_language: "en",
      distillator_mode: "shadow"
    )
    non_cohort = Website.create!(
      name: "Outside Feed",
      seedurl: "outside-feed",
      graph_name: "http://example.com/outside-feed",
      default_language: "en",
      distillator_mode: "shadow"
    )

    get websites_url, params: { cohort: "lavitrine_pipeline" }

    assert_response :success
    assert_includes @response.body, cohort.name
    assert_not_includes @response.body, non_cohort.name
    assert_includes @response.body, 'name="cohort"'
    assert_no_cohort_source_requests
  end

  test "website show shows la vitrine badge without external requests" do
    website = Website.create!(
      name: "Hector Charland",
      seedurl: "hector-charland-com",
      graph_name: "http://example.com/tout-culture",
      default_language: "en",
      distillator_mode: "shadow"
    )

    get website_url(website)

    assert_response :success
    assert_includes @response.body, "La Vitrine pipeline"
    assert_no_cohort_source_requests
  end

  test "website show renders active rollout badge without exposing internal wording" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "active")

    get website_url(@website)

    assert_response :success
    assert_includes @response.body, "Active"
    assert_includes @response.body, "Condenser"
    assert_includes @response.body, "Rollback to Legacy Wringer"
    assert_not_includes @response.body, "internal"
  end

  test "website show does not render stale rollout warning copy" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "legacy")

    get website_url(@website)

    assert_response :success
    assert_includes @response.body, "Move to Shadow."
    refute_includes @response.body, "Legacy mode keeps Wringer as the active fetch path."
  end

  test "website show for legacy shows simple transition controls when override is allowed" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "legacy")

    get website_url(@website)

    assert_response :success
    assert_includes @response.body, "Move to shadow"
    assert_includes @response.body, "Run transition check"
    assert_includes @response.body, "Activate anyway"
    assert_includes @response.body, "Use after manual inspection or on staging. Records current blockers and reason."
  end

  test "website show for shadow shows readiness summary and transition check" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "shadow")

    get website_url(@website)

    assert_response :success
    assert_includes @response.body, "Readiness:"
    assert_includes @response.body, "Run transition check"
  end

  test "website show for shadow ready site shows promote to active action" do
    assert_read_only_page_does_not_fetch
    website = ready_shadow_website(seedurl: "shadow-ready-show")

    get website_url(website)

    assert_response :success
    assert_includes @response.body, "Promote to active"
    assert_includes @response.body, "Ready for active promotion."
    assert_not_includes @response.body, "Cannot promote yet"
  end

  test "website show for shadow blocked site shows blockers and transition check" do
    assert_read_only_page_does_not_fetch
    website = blocked_shadow_website(seedurl: "shadow-blocked-show")

    get website_url(website)

    assert_response :success
    assert_includes @response.body, "Cannot promote yet"
    assert_includes @response.body, "Cannot activate yet: statements check failed."
    assert_includes @response.body, "Run transition check"
  end

  test "website show hides activate anyway when override is not allowed" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "shadow")
    Distillator::TransitionRuntime.stubs(:allow_active_override?).returns(false)

    get website_url(@website)

    assert_response :success
    assert_not_includes @response.body, "Activate anyway"
  end

  test "website show keeps rollout copy compact and destructive actions collapsed" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "legacy")

    get website_url(@website)

    assert_response :success
    assert_operator @response.body.scan("Legacy").length, :>=, 1
    assert_operator @response.body.scan("Wringer remains the production fetch path").length, :<=, 1
    assert_includes @response.body, "Open Condenser cache"
    assert_includes @response.body, "Refresh upcoming events"
    assert_includes @response.body, "Destroy website"
    assert_not_includes @response.body, "Back"
    assert_select "details.website-danger-zone[open]", 0
    assert_select "details.website-danger-zone summary", text: "Danger zone"
    assert_select "details.website-danger-zone form", 4
  end

  test "should get edit" do
    get edit_website_url(@website)
    assert_response :success
    assert_includes @response.body, 'name="website[distillator_mode]"'
    assert_includes @response.body, ">Legacy<"
    assert_includes @response.body, ">Shadow<"
    assert_includes @response.body, ">Active<"
    assert_includes @response.body, "Use the website Transition card for normal promotion, override, and rollback."
    assert_not_includes @response.body, "Show"
    assert_not_includes @response.body, "Back"
    assert_not_includes @response.body, "new cache"
    assert_not_includes @response.body, ">internal<"
  end

  test "should update website" do
    patch website_url(@website), params: { website: { name: @website.name, seedurl: @website.seedurl, distillator_mode: "active" } }
    assert_response :success
    assert_equal "legacy", @website.reload.distillator_mode
  end

  test "activate anyway requires a reason" do
    website = Website.create!(
      name: "Override reason required",
      seedurl: "override-reason-required",
      graph_name: "https://example.org/override-reason-required",
      default_language: "en",
      distillator_mode: "legacy"
    )

    post activate_anyway_website_path(website), params: { reason: "" }

    assert_redirected_to website_url(website)
    assert_equal "legacy", website.reload.distillator_mode
    follow_redirect!
    assert_includes @response.body, "Reason is required for Activate anyway"
  end

  test "activate anyway succeeds in test runtime and records override details" do
    website = Website.create!(
      name: "Override success",
      seedurl: "override-success",
      graph_name: "https://example.org/override-success",
      default_language: "en",
      distillator_mode: "shadow"
    )
    website.transition_evidences.create!(
      url: "https://example.org/override-success",
      check_kind: "fetch_parity",
      status: "pending",
      checked_at: 1.hour.ago
    )

    post activate_anyway_website_path(website), params: { reason: "Manual inspection complete" }

    assert_redirected_to website_url(website)
    assert_equal "active", website.reload.distillator_mode
    event = website.rollout_events.order(:created_at).last
    assert_equal "Manual inspection complete", event.reason
    assert_equal true, event.readiness_snapshot["override"]
    assert_equal "rollout.override", event.readiness_snapshot["event"]
    assert event.readiness_snapshot["blockers"].is_a?(Array)
    assert event.readiness_snapshot["warnings"].is_a?(Array)
  end

  test "la vitrine shadow site cannot be promoted to active with missing export evidence" do
    website = Website.create!(
      name: "Hector Charland",
      seedurl: "hector-charland-com",
      graph_name: "https://example.org/hector-charland",
      default_language: "en",
      distillator_mode: "shadow"
    )

    patch website_url(website), params: { website: { distillator_mode: "active" } }

    assert_response :success
    assert_equal "shadow", website.reload.distillator_mode
    assert_includes @response.body, "Cannot activate yet: export check is missing."
  end

  test "la vitrine shadow site can be promoted when durable readiness blockers are empty" do
    website = Website.create!(
      name: "Hector Charland",
      seedurl: "hector-charland-com",
      graph_name: "https://example.org/hector-charland",
      default_language: "en",
      distillator_mode: "shadow"
    )
    url = "https://hector-charland-com.example/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:hector-ready", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: url
    )
    website.transition_evidences.create!(url: url, check_kind: "fetch_parity", status: "checked", details: { representative_urls_checked: true }, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: url, check_kind: "statement_delta", status: "checked", statement_count_delta_acceptable: true, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: url, check_kind: "export_diff", status: "checked", export_diff_checked: true, checked_at: 1.hour.ago)

    patch website_url(website), params: { website: { distillator_mode: "active" } }

    assert_redirected_to website_url(website)
    assert_equal "active", website.reload.distillator_mode
  end

  test "ordinary shadow site cannot be promoted when checks need review" do
    website = Website.create!(
      name: "Review site",
      seedurl: "review-site",
      graph_name: "https://example.org/review-site",
      default_language: "en",
      distillator_mode: "shadow"
    )
    url = "https://review-site.example/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:review-site", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: url
    )

    patch website_url(website), params: { website: { distillator_mode: "active" } }

    assert_response :success
    assert_equal "shadow", website.reload.distillator_mode
    assert_includes @response.body, "Cannot activate yet: statements check is missing."
  end

  test "active to legacy rollback is allowed even when readiness would fail" do
    website = Website.create!(
      name: "Rollback site",
      seedurl: "hector-charland-com",
      graph_name: "https://example.org/rollback",
      default_language: "en",
      distillator_mode: "active"
    )

    patch website_url(website), params: { website: { distillator_mode: "legacy" } }

    assert_redirected_to website_url(website)
    assert_equal "legacy", website.reload.distillator_mode
    assert_equal "rollout.rollback", website.rollout_events.order(:created_at).last.readiness_snapshot["event"]
  end

  test "invalid distillator_mode is rejected" do
    original_mode = @website.distillator_mode

    patch website_url(@website), params: { website: { distillator_mode: "internal" } }

    assert_response :success
    assert_equal original_mode, @website.reload.distillator_mode
    assert_includes @response.body, "Distillator mode is not included in the list"
  end

  test "replay distillator_mode is rejected and preserves prior mode" do
    original_mode = @website.distillator_mode

    patch website_url(@website), params: { website: { distillator_mode: "replay" } }

    assert_response :success
    assert_equal original_mode, @website.reload.distillator_mode
    assert_includes @response.body, "Distillator mode is not included in the list"
  end

  test "blank distillator_mode is rejected and preserves prior mode" do
    @website.update!(distillator_mode: "shadow")

    patch website_url(@website), params: { website: { distillator_mode: "" } }

    assert_response :success
    assert_equal "shadow", @website.reload.distillator_mode
    assert_includes @response.body, "Distillator mode is not included in the list"
  end

  test "random distillator_mode is rejected and preserves prior mode" do
    @website.update!(distillator_mode: "active")

    patch website_url(@website), params: { website: { distillator_mode: "banana" } }

    assert_response :success
    assert_equal "active", @website.reload.distillator_mode
    assert_includes @response.body, "Distillator mode is not included in the list"
  end

  test "should destroy website" do
    assert_difference('Website.count', -1) do
      delete website_url(@website)
    end

    assert_redirected_to websites_url
  end

  test "index sorts by selected column and direction" do
    Website.create!(
      name: "sort-target-b",
      seedurl: "sort-target-b",
      graph_name: "http://example.com/b",
      default_language: "en"
    )
    Website.create!(
      name: "sort-target-a",
      seedurl: "sort-target-a",
      graph_name: "http://example.com/a",
      default_language: "en"
    )

    get websites_url, params: { q: "sort-target", sort: "name", direction: "asc" }
    assert_response :success
    body = @response.body
    assert_operator body.index("sort-target-a"), :<, body.index("sort-target-b")

    get websites_url, params: { q: "sort-target", sort: "name", direction: "desc" }
    assert_response :success
    body = @response.body
    assert_operator body.index("sort-target-b"), :<, body.index("sort-target-a")
  end

  test "index preserves q in sortable links and toggles direction" do
    get websites_url, params: { q: "sort-target", sort: "name", direction: "asc" }
    assert_response :success
    assert_includes @response.body, "q=sort-target"
    assert_includes @response.body, "sort=name"
    assert_includes @response.body, "direction=desc"
  end

  test "index shows direction indicator on active sort column" do
    get websites_url, params: { sort: "name", direction: "asc" }
    assert_response :success
    assert_includes @response.body, "Name ↑"

    get websites_url, params: { sort: "name", direction: "desc" }
    assert_response :success
    assert_includes @response.body, "Name ↓"
  end

  test "index falls back to safe defaults for invalid sort parameters" do
    Website.create!(
      name: "sort-safe-a",
      seedurl: "sort-safe-a",
      graph_name: "http://example.com/safe-a",
      default_language: "en"
    )
    Website.create!(
      name: "sort-safe-b",
      seedurl: "sort-safe-b",
      graph_name: "http://example.com/safe-b",
      default_language: "en"
    )

    get websites_url, params: { q: "sort-safe", sort: "name;DROP TABLE websites", direction: "sideways" }
    assert_response :success
    body = @response.body
    assert_operator body.index("sort-safe-a"), :<, body.index("sort-safe-b")
  end

  test "index sorts computed webpages_count numerically and treats missing values as zero" do
    zero = Website.create!(
      name: "computed webpages zero",
      seedurl: "computed-webpages-zero",
      graph_name: "http://example.com/computed-webpages-zero",
      default_language: "en"
    )
    two = Website.create!(
      name: "computed webpages two",
      seedurl: "computed-webpages-two",
      graph_name: "http://example.com/computed-webpages-two",
      default_language: "en"
    )
    ten = Website.create!(
      name: "computed webpages ten",
      seedurl: "computed-webpages-ten",
      graph_name: "http://example.com/computed-webpages-ten",
      default_language: "en"
    )

    2.times do |index|
      Webpage.create!(
        url: "http://example.com/computed-two/#{index}",
        language: "en",
        rdf_uri: "computed-two-#{two.id}-#{index}",
        rdfs_class: rdfs_classes(:one),
        website: two
      )
    end

    10.times do |index|
      Webpage.create!(
        url: "http://example.com/computed-ten/#{index}",
        language: "en",
        rdf_uri: "computed-ten-#{ten.id}-#{index}",
        rdfs_class: rdfs_classes(:one),
        website: ten
      )
    end

    get websites_url, params: { q: "computed webpages", sort: "webpages_count", direction: "asc" }
    assert_response :success
    body = @response.body
    assert_operator body.index(zero.name), :<, body.index(two.name)
    assert_operator body.index(two.name), :<, body.index(ten.name)

    get websites_url, params: { q: "computed webpages", sort: "webpages_count", direction: "desc" }
    assert_response :success
    body = @response.body
    assert_operator body.index(ten.name), :<, body.index(two.name)
    assert_operator body.index(two.name), :<, body.index(zero.name)
  end

  test "index filters by seedurl partial match" do
    Website.create!(
      name: "seed filter one",
      seedurl: "seed-match",
      graph_name: "http://example.com/seed-one",
      default_language: "en"
    )
    Website.create!(
      name: "seed filter two",
      seedurl: "other-seed-two",
      graph_name: "http://example.com/seed-two",
      default_language: "en"
    )

    get websites_url, params: { seed_filter: "seed-match" }
    assert_response :success
    assert_includes @response.body, "seed-match"
    assert_not_includes @response.body, "other-seed-two"
  end

  test "index filters by q case-insensitively" do
    Website.create!(
      name: "Culture Alpha",
      seedurl: "culture-alpha",
      graph_name: "http://example.com/culture-alpha",
      default_language: "en"
    )
    Website.create!(
      name: "culture Beta",
      seedurl: "culture-beta",
      graph_name: "http://example.com/culture-beta",
      default_language: "en"
    )

    get websites_url, params: { q: "cultu" }
    assert_response :success
    assert_includes @response.body, "Culture Alpha"
    assert_includes @response.body, "culture Beta"
  end

  test "index filters by default_language exact match" do
    Website.create!(
      name: "lang filter en",
      seedurl: "lang-filter-en",
      graph_name: "http://example.com/lang-en",
      default_language: "en"
    )
    Website.create!(
      name: "lang filter fr",
      seedurl: "lang-filter-fr",
      graph_name: "http://example.com/lang-fr",
      default_language: "fr"
    )

    get websites_url, params: { default_language: "fr" }
    assert_response :success
    assert_includes @response.body, "lang-filter-fr"
    assert_not_includes @response.body, "lang-filter-en"
  end

  test "websites index filters by legacy distillator mode" do
    legacy = Website.create!(
      name: "legacy rollout site",
      seedurl: "legacy-rollout-site",
      graph_name: "http://example.com/legacy-rollout-site",
      default_language: "en",
      distillator_mode: "legacy"
    )
    shadow = Website.create!(
      name: "shadow rollout site",
      seedurl: "shadow-rollout-site",
      graph_name: "http://example.com/shadow-rollout-site",
      default_language: "en",
      distillator_mode: "shadow"
    )

    get websites_url, params: { distillator_mode: "legacy" }

    assert_response :success
    assert_includes @response.body, legacy.name
    assert_not_includes @response.body, shadow.name
  end

  test "websites index filters by shadow distillator mode" do
    legacy = Website.create!(
      name: "legacy rollout site",
      seedurl: "legacy-rollout-site",
      graph_name: "http://example.com/legacy-rollout-site",
      default_language: "en",
      distillator_mode: "legacy"
    )
    shadow = Website.create!(
      name: "shadow rollout site",
      seedurl: "shadow-rollout-site",
      graph_name: "http://example.com/shadow-rollout-site",
      default_language: "en",
      distillator_mode: "shadow"
    )

    get websites_url, params: { distillator_mode: "shadow" }

    assert_response :success
    assert_includes @response.body, shadow.name
    assert_not_includes @response.body, legacy.name
    assert_includes @response.body, 'name="distillator_mode"'
  end

  test "websites index filters by active distillator mode" do
    active = Website.create!(
      name: "active rollout site",
      seedurl: "active-rollout-site",
      graph_name: "http://example.com/active-rollout-site",
      default_language: "en",
      distillator_mode: "active"
    )
    legacy = Website.create!(
      name: "legacy rollout site two",
      seedurl: "legacy-rollout-site-two",
      graph_name: "http://example.com/legacy-rollout-site-two",
      default_language: "en",
      distillator_mode: "legacy"
    )

    get websites_url, params: { distillator_mode: "active" }

    assert_response :success
    assert_includes @response.body, active.name
    assert_not_includes @response.body, legacy.name
  end

  test "websites index ignores invalid distillator mode safely" do
    safe = Website.create!(
      name: "safe rollout site",
      seedurl: "safe-rollout-site",
      graph_name: "http://example.com/safe-rollout-site",
      default_language: "en",
      distillator_mode: "legacy"
    )

    get websites_url, params: { distillator_mode: "shadow;DROP TABLE websites" }

    assert_response :redirect
    assert_redirected_to "/websites"
    follow_redirect!
    assert_response :success
    assert_includes @response.body, safe.name
  end

  test "websites index filters by unknown unset distillator mode" do
    Website.create!(
      name: "unknown rollout blank",
      seedurl: "unknown-rollout-blank",
      graph_name: "http://example.com/unknown-rollout-blank",
      default_language: "en",
      distillator_mode: "legacy"
    ).update_column(:distillator_mode, "")
    Website.create!(
      name: "known rollout active",
      seedurl: "known-rollout-active",
      graph_name: "http://example.com/known-rollout-active",
      default_language: "en",
      distillator_mode: "active"
    )

    get websites_url, params: { distillator_mode: "unknown" }

    assert_response :success
    assert_includes @response.body, "unknown rollout blank"
    assert_not_includes @response.body, "known rollout active"
  end

  test "websites index shows staging warning and invalid on staging summary link" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    @website.update!(distillator_mode: "legacy")

    get websites_url

    assert_response :success
    assert_includes @response.body, "Staging requires every website to be Shadow or Active."
    assert_select 'a[href="/websites?distillator_mode=invalid_on_staging"]', text: /Invalid on staging:/
  ensure
    ENV["DISTILLATOR_RUNTIME"] = nil
  end

  test "websites index filters invalid on staging rows" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    Website.create!(
      name: "Legacy invalid website filter",
      seedurl: "legacy-invalid-website-filter",
      graph_name: "http://example.com/legacy-invalid-website-filter",
      default_language: "en",
      distillator_mode: "legacy"
    )
    Website.create!(
      name: "Active valid website filter",
      seedurl: "active-valid-website-filter",
      graph_name: "http://example.com/active-valid-website-filter",
      default_language: "en",
      distillator_mode: "active"
    )

    get websites_url, params: { distillator_mode: "invalid_on_staging" }

    assert_response :success
    assert_includes @response.body, "Legacy invalid website filter"
    assert_not_includes @response.body, "Active valid website filter"
  ensure
    ENV["DISTILLATOR_RUNTIME"] = nil
  end

  test "index filters by graph_name partial match" do
    Website.create!(
      name: "graph filter one",
      seedurl: "graph-filter-one",
      graph_name: "http://example.com/graph-match",
      default_language: "en"
    )
    Website.create!(
      name: "graph filter two",
      seedurl: "graph-filter-two",
      graph_name: "http://example.com/graph-other",
      default_language: "en"
    )

    get websites_url, params: { graph_name: "graph-match" }
    assert_response :success
    assert_includes @response.body, "graph-filter-one"
    assert_not_includes @response.body, "graph-filter-two"
  end

  test "index composes filtering with sorting" do
    Website.create!(
      name: "compose sort b",
      seedurl: "compose-seed",
      graph_name: "http://example.com/compose-b",
      default_language: "en"
    )
    Website.create!(
      name: "compose sort a",
      seedurl: "compose-seed",
      graph_name: "http://example.com/compose-a",
      default_language: "en"
    )
    Website.create!(
      name: "compose sort outside",
      seedurl: "outside-seed",
      graph_name: "http://example.com/compose-outside",
      default_language: "en"
    )

    get websites_url, params: { seed_filter: "compose-seed", sort: "name", direction: "asc" }
    assert_response :success
    body = @response.body
    assert_operator body.index("compose sort a"), :<, body.index("compose sort b")
    assert_not_includes body, "compose sort outside"
  end

  test "websites index preserves distillator mode filter in sort links" do
    get websites_url, params: { distillator_mode: "shadow", q: "sort-target", sort: "name", direction: "asc" }

    assert_response :success
    assert_sort_link_preserves_params(
      label: "Name",
      sort_key: "name",
      params: { distillator_mode: "shadow", q: "sort-target" }
    )
  end

  test "websites index reset filters clears distillator mode" do
    get websites_url, params: { distillator_mode: "shadow", q: "needle" }

    assert_response :success
    assert_harmonized_reset_filters_link(path: "/websites")
    assert_select 'a[href="/websites"]', text: "Reset filters"
  end

  test "index handles empty or invalid filter params without breaking" do
    get websites_url, params: { q: "", seed_filter: "", default_language: "xx", graph_name: "" }
    assert_response :success
  end

  test "index with blank filters shows unfiltered results" do
    Website.create!(
      name: "blank-filter-one",
      seedurl: "blank-filter-seed-1",
      graph_name: "http://example.com/blank-one",
      default_language: "en"
    )
    Website.create!(
      name: "blank-filter-two",
      seedurl: "blank-filter-seed-2",
      graph_name: "http://example.com/blank-two",
      default_language: "fr"
    )

    get websites_url, params: { q: "", seed_filter: "", default_language: "", graph_name: "" }
    assert_response :success
    assert_includes @response.body, "blank-filter-one"
    assert_includes @response.body, "blank-filter-two"
  end

  test "index treats wildcard as a literal filter value" do
    get websites_url, params: { q: "*", seed_filter: "*", graph_name: "*" }
    assert_response :success
    assert_not_includes @response.body, websites(:one).name
    assert_not_includes @response.body, websites(:two).name
  end

  test "websites index renders active cache link in legacy and internal modes" do
    assert_read_only_page_does_not_fetch

    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    get websites_url
    assert_response :success
    assert_includes @response.body, "Open active cache"

    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    get websites_url
    assert_response :success
    assert_includes @response.body, "Open active cache"
  end

  test "websites index renders rollout badge for legacy website" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "legacy")

    get websites_url

    assert_response :success
    assert_includes @response.body, "Legacy"
    assert_not_includes @response.body, ">legacy<"
  end

  test "websites index renders rollout badge for shadow website" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "shadow")

    get websites_url

    assert_response :success
    assert_includes @response.body, "Shadow"
    assert_not_includes @response.body, ">shadow<"
  end

  test "websites index renders rollout badge for active website" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "active")

    get websites_url

    assert_response :success
    assert_includes @response.body, "Active"
    assert_not_includes @response.body, ">active<"
  end

  test "websites index renders safe fallback for unknown rollout mode" do
    assert_read_only_page_does_not_fetch
    @website.update_column(:distillator_mode, "")

    get websites_url

    assert_response :success
    assert_includes @response.body, "Unknown"
  end

  test "websites index rollout badges do not expose internal mode names" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "active")

    get websites_url

    assert_response :success
    assert_not_includes @response.body, ">internal<"
  end

  test "website detail shows rollout panel for legacy website" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "legacy")

    get website_url(@website)

    assert_response :success
    assert_includes @response.body, "Transition"
    assert_includes @response.body, "Current mode:</strong> Legacy"
    assert_includes @response.body, "Production backend:</strong> Wringer"
    assert_includes @response.body, "Next recommended action:</strong> Move to Shadow."
    assert_includes @response.body, "Move to shadow"
    assert_includes @response.body, "Open Condenser cache"
  end

  test "website detail shows rollout panel for shadow website" do
    assert_read_only_page_does_not_fetch
    stub_remote_wringer_endpoint
    website = ready_shadow_website(seedurl: "rollout-panel-shadow")

    get website_url(website)

    assert_response :success
    assert_includes @response.body, "Current mode:</strong> Shadow"
    assert_includes @response.body, "Production backend:</strong> Wringer"
    assert_includes @response.body, "Readiness:</strong>"
    assert_includes @response.body, "Promote to active"
    assert_includes @response.body, "Run transition check"
    assert_includes @response.body, "Compare Condenser vs Wringer"
  end

  test "website detail shows rollout panel for active website" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "active")

    get website_url(@website)

    assert_response :success
    assert_includes @response.body, "Current mode:</strong> Active"
    assert_includes @response.body, "Production backend:</strong> Condenser"
    assert_includes @response.body, "Latest rollout event:</strong>"
    assert_includes @response.body, "Rollback to Legacy Wringer"
  end

  test "website detail shows comparison link only for shadow website" do
    assert_read_only_page_does_not_fetch
    stub_remote_wringer_endpoint
    @website.update!(distillator_mode: "shadow")

    get website_url(@website)

    assert_response :success
    assert_includes @response.body, "Compare Condenser vs Wringer"
  end

  test "website detail shows legacy inspection link for active website" do
    assert_read_only_page_does_not_fetch
    stub_remote_wringer_endpoint
    @website.update!(distillator_mode: "active")

    get website_url(@website)

    assert_response :success
    assert_includes @response.body, "Inspect legacy Wringer"
  end

  test "website detail rollout panel does not fetch" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "shadow")

    get website_url(@website)

    assert_response :success
  end

  test "website rollout panel uses centralized operator copy and avoids retired wording" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "active")

    get website_url(@website)

    assert_response :success
    assert_includes @response.body, "Transition"
    assert_includes @response.body, Distillator::RolloutCopy.label(:active)
    assert_not_includes @response.body, Distillator::RolloutCopy.rollout_panel_title
    assert_not_includes @response.body, "Distillator rollout"
    assert_not_includes @response.body, "internal"
    assert_not_includes @response.body, "new cache"
    assert_not_includes @response.body, "phase I"
    assert_not_includes @response.body, "preview only"
    assert_not_includes @response.body, "first UI batch"
  end

  test "websites index shows rollout summary counts" do
    Website.create!(
      name: "summary shadow",
      seedurl: "summary-shadow",
      graph_name: "http://example.com/summary-shadow",
      default_language: "en",
      distillator_mode: "shadow"
    )

    get websites_url

    assert_response :success
    assert_includes @response.body, "Legacy:"
    assert_includes @response.body, "Shadow:"
    assert_includes @response.body, "Active:"
    assert_includes @response.body, "Unknown:"
  end

  test "websites index summary counts include legacy shadow active and unknown" do
    Website.create!(
      name: "summary legacy",
      seedurl: "summary-legacy",
      graph_name: "http://example.com/summary-legacy",
      default_language: "en",
      distillator_mode: "legacy"
    )
    Website.create!(
      name: "summary active",
      seedurl: "summary-active",
      graph_name: "http://example.com/summary-active",
      default_language: "en",
      distillator_mode: "active"
    )
    Website.create!(
      name: "summary unknown",
      seedurl: "summary-unknown",
      graph_name: "http://example.com/summary-unknown",
      default_language: "en",
      distillator_mode: "legacy"
    ).update_column(:distillator_mode, "")

    get websites_url

    assert_response :success
    assert_select 'a[href="/websites?distillator_mode=legacy"]', text: /Legacy:/
    assert_select 'a[href="/websites?distillator_mode=shadow"]', text: /Shadow:/
    assert_select 'a[href="/websites?distillator_mode=active"]', text: /Active:/
    assert_select 'a[href="/websites?distillator_mode=unknown"]', text: /Unknown:/
  end

  test "websites index summary counts remain global when search is applied" do
    Website.create!(
      name: "global legacy count",
      seedurl: "global-legacy-count",
      graph_name: "http://example.com/global-legacy-count",
      default_language: "en",
      distillator_mode: "legacy"
    )
    Website.create!(
      name: "global shadow count",
      seedurl: "global-shadow-count",
      graph_name: "http://example.com/global-shadow-count",
      default_language: "en",
      distillator_mode: "shadow"
    )

    get websites_url, params: { q: "global legacy count" }

    assert_response :success
    assert_includes @response.body, "Shadow: 1"
  end

  test "websites index does not fetch" do
    assert_read_only_page_does_not_fetch

    get websites_url

    assert_response :success
  end

  test "website edit does not fetch" do
    assert_read_only_page_does_not_fetch

    get edit_website_url(@website)

    assert_response :success
  end

  test "website new does not fetch" do
    assert_read_only_page_does_not_fetch

    get new_website_url

    assert_response :success
  end

  private

  def ready_shadow_website(seedurl:)
    website = Website.create!(
      name: "Ready shadow #{seedurl}",
      seedurl: seedurl,
      graph_name: "https://example.org/#{seedurl}",
      default_language: "en",
      distillator_mode: "shadow"
    )
    url = "https://example.org/#{seedurl}/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:#{seedurl}", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: url
    )
    website.transition_evidences.create!(url: url, check_kind: "fetch_parity", status: "checked", details: { representative_urls_checked: true }, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: url, check_kind: "statement_delta", status: "checked", statement_count_delta_acceptable: true, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: url, check_kind: "export_diff", status: "checked", export_diff_checked: true, checked_at: 1.hour.ago)
    website
  end

  def blocked_shadow_website(seedurl:)
    website = Website.create!(
      name: "Blocked shadow #{seedurl}",
      seedurl: seedurl,
      graph_name: "https://example.org/#{seedurl}",
      default_language: "en",
      distillator_mode: "shadow"
    )
    url = "https://example.org/#{seedurl}/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:#{seedurl}", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: url
    )
    website.transition_evidences.create!(
      url: url,
      check_kind: "statement_delta",
      status: "failed",
      statement_count_delta_acceptable: false,
      checked_at: 1.hour.ago
    )
    website
  end

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

  def assert_no_cohort_source_requests
    WebMock.assert_not_requested(:any, Distillator::Cohorts::LavitrinePipeline.query_url)
  end

  def stub_remote_wringer_endpoint
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
end
