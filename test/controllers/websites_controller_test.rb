require 'test_helper'

class WebsitesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @website = websites(:one)
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
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
    assert_includes @response.body, "Legacy Wringer active:"
    assert_includes @response.body, "Shadow comparison:"
    assert_includes @response.body, "Condenser active:"
    assert_includes @response.body, "Unknown rollout:"
    assert_includes @response.body, "La Vitrine pipeline"
    assert_includes @response.body, "Website rollout filters"
    assert_select 'details[data-operator-context-card]', 0
    assert_no_cohort_source_requests
  end

  test "should get new" do
    get new_website_url
    assert_response :success
    assert_includes @response.body, 'name="website[distillator_mode]"'
    assert_includes @response.body, "Legacy - Wringer active"
    assert_includes @response.body, "Shadow - Wringer production path + Condenser comparison"
    assert_includes @response.body, "Active - Condenser active"
    assert_includes @response.body, "Wringer remains the production fetch path."
    assert_includes @response.body, "Wringer serves production results; Condenser compares in the background."
    assert_includes @response.body, "Condenser serves fetch/cache results; legacy Wringer remains available for inspection."
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
    @website.update!(distillator_mode: "shadow")
    get website_url(@website)
    assert_response :success
    assert_select 'details[data-operator-context-card]'
    assert_select 'details[data-context-domain="status"]'
    assert_select 'details[data-context-domain="actions"]'
    assert_select 'details[data-context-domain="details"]'
    assert_includes @response.body, Distillator::RolloutCopy.rollout_panel_title
    assert_includes @response.body, "Current mode:"
    assert_includes @response.body, "Production backend:"
    assert_includes @response.body, "Next step:"
    assert_includes @response.body, "Shadow comparison"
    assert_includes @response.body, "Wringer"
    assert_includes @response.body, "Compare Condenser output before promotion."
    assert_includes @response.body, "Compare Condenser vs Wringer"
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
    assert_includes @response.body, "Condenser active"
    assert_includes @response.body, "Condenser"
    assert_includes @response.body, "Inspect legacy Wringer"
    assert_not_includes @response.body, "internal"
  end

  test "website show does not render stale rollout warning copy" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "legacy")

    get website_url(@website)

    assert_response :success
    assert_includes @response.body, "Inspect Condenser cache before promotion."
    refute_includes @response.body, "Legacy mode keeps Wringer as the active fetch path."
  end

  test "should get edit" do
    get edit_website_url(@website)
    assert_response :success
    assert_includes @response.body, 'name="website[distillator_mode]"'
    assert_includes @response.body, "Legacy - Wringer active"
    assert_includes @response.body, "Shadow - Wringer production path + Condenser comparison"
    assert_includes @response.body, "Active - Condenser active"
    assert_not_includes @response.body, "new cache"
    assert_not_includes @response.body, ">internal<"
  end

  test "should update website" do
    patch website_url(@website), params: { website: { name: @website.name, seedurl: @website.seedurl, distillator_mode: "active" } }
    assert_response :success
    assert_equal "legacy", @website.reload.distillator_mode
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
    assert_includes @response.body, "Legacy Wringer active"
    assert_not_includes @response.body, ">legacy<"
  end

  test "websites index renders rollout badge for shadow website" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "shadow")

    get websites_url

    assert_response :success
    assert_includes @response.body, "Shadow comparison"
    assert_not_includes @response.body, ">shadow<"
  end

  test "websites index renders rollout badge for active website" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "active")

    get websites_url

    assert_response :success
    assert_includes @response.body, "Condenser active"
    assert_not_includes @response.body, ">active<"
  end

  test "websites index renders safe fallback for unknown rollout mode" do
    assert_read_only_page_does_not_fetch
    @website.update_column(:distillator_mode, "")

    get websites_url

    assert_response :success
    assert_includes @response.body, "Unknown rollout"
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
    assert_includes @response.body, Distillator::RolloutCopy.rollout_panel_title
    assert_includes @response.body, "Current mode:</strong> Legacy Wringer active"
    assert_includes @response.body, "Production backend:</strong> Wringer"
    assert_includes @response.body, "Next step:</strong> Inspect Condenser cache before promotion."
    assert_includes @response.body, "Open Condenser cache"
  end

  test "website detail shows rollout panel for shadow website" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "shadow")

    get website_url(@website)

    assert_response :success
    assert_includes @response.body, "Current mode:</strong> Shadow comparison"
    assert_includes @response.body, "Production backend:</strong> Wringer"
    assert_includes @response.body, "Next step:</strong> Compare Condenser output before promotion."
    assert_includes @response.body, "Compare Condenser vs Wringer"
  end

  test "website detail shows rollout panel for active website" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "active")

    get website_url(@website)

    assert_response :success
    assert_includes @response.body, "Current mode:</strong> Condenser active"
    assert_includes @response.body, "Production backend:</strong> Condenser"
    assert_includes @response.body, "Next step:</strong> Inspect legacy Wringer when validating parity."
  end

  test "website detail shows comparison link only for shadow website" do
    assert_read_only_page_does_not_fetch
    @website.update!(distillator_mode: "shadow")

    get website_url(@website)

    assert_response :success
    assert_includes @response.body, "Compare Condenser vs Wringer"
  end

  test "website detail shows legacy inspection link for active website" do
    assert_read_only_page_does_not_fetch
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
    assert_includes @response.body, Distillator::RolloutCopy.rollout_panel_title
    assert_includes @response.body, Distillator::RolloutCopy.label(:active)
    assert_includes @response.body, Distillator::RolloutCopy.description(:active)
    assert_not_includes @response.body, "Distillator rollout"
    assert_not_includes @response.body, "internal"
    assert_not_includes @response.body, "new cache"
    assert_not_includes @response.body, "phase I"
    assert_not_includes @response.body, "preview only"
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
    assert_includes @response.body, "Legacy Wringer active:"
    assert_includes @response.body, "Shadow comparison:"
    assert_includes @response.body, "Condenser active:"
    assert_includes @response.body, "Unknown rollout:"
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
    assert_select 'a[href="/websites?distillator_mode=legacy"]', text: /Legacy Wringer active:/
    assert_select 'a[href="/websites?distillator_mode=shadow"]', text: /Shadow comparison:/
    assert_select 'a[href="/websites?distillator_mode=active"]', text: /Condenser active:/
    assert_select 'a[href="/websites?distillator_mode=unknown"]', text: /Unknown rollout:/
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
    assert_includes @response.body, "Shadow comparison: 1"
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

  def assert_read_only_page_does_not_fetch
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never
  end

  def assert_no_cohort_source_requests
    WebMock.assert_not_requested(:any, Distillator::Cohorts::LavitrinePipeline.query_url)
  end
end
