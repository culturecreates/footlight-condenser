require "test_helper"

class Distillator::TransitionExclusionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @website = Website.create!(name: "Exclusion workflow", seedurl: "petittheatre-org", default_language: "en",
      graph_name: "https://example.org/exclusion-workflow", distillator_mode: "shadow")
    @pages = 9.times.map do |index|
      @website.webpages.create!(url: "https://example.org/event/#{index}", rdf_uri: "https://example.org/rdf/#{index}",
        rdfs_class: rdfs_classes(:one), language: "en")
    end
    { "Title" => ["title", "Event"], "Location" => ["address", "Hall"], "Dates" => ["time", "2027-01-01"] }.each do |label, (tag, value)|
      property = Property.create!(label: label, rdfs_class: rdfs_classes(:one), uri: "https://example.org/property/#{label}", value_datatype: "MyString")
      source = @website.sources.create!(property: property, language: "en", selected: true, algorithm_value: "xpath=//#{tag}/text()")
      @pages.each { |page| Statement.create!(webpage: page, source: source, cache: value, status: "ok") }
    end
    Statement.where(webpage: @pages).update_all(status: "ok")
    @gone = @pages.last
    @run = publish_unavailable_source_run(@website, url: @gone.url)
  end

  test "bilateral unavailability offers a reason form and creating a review preserves old results" do
    get distillator_shadow_report_site_path(@website, run_id: @run.id)
    assert_response :success
    assert_select '.transition-source-unavailable', text: /Source unavailable on both backends/
    assert_select 'form[action="/distillator/transition_exclusions"] textarea[name="reason"][required]', count: 1
    before = @run.transition_evidences.map(&:attributes)
    assert_difference "Distillator::TransitionExclusion.count", 1 do
      assert_no_difference ["Webpage.count", "Statement.count", "Distillator::TransitionRun.count"] do
        post_review
      end
    end
    assert_redirected_to distillator_shadow_report_site_path(@website)
    follow_redirect!
    assert_select '.transition-decision h2', text: "Scope or configuration changed — run a new check"
    assert_select '#transition-reviewed-exclusions', text: /apply to the next check/
    assert_select '.transition-next-action form[action="/distillator/transition_checks"]'
    assert_select 'form[action="/distillator/transition_exclusions"]', count: 0
    assert_equal before, @run.transition_evidences.map(&:attributes)
    assert_equal "shadow", @website.reload.distillator_mode
  end

  test "blank reasons and forged URLs are rejected and cross website runs are not found" do
    assert_no_difference "Distillator::TransitionExclusion.count" do
      post_review(reason: " ")
      assert_includes flash[:alert], "Reason"
      post_review(url: @pages.first.url)
      assert_includes flash[:alert], "Both backends"
      post distillator_transition_exclusions_path, params: { website_id: websites(:one).id, source_run_id: @run.id, url: @gone.url, reason: "Removed" }
      assert_response :not_found
    end
  end

  test "restore keeps the review record and requires a new comparison" do
    post_review
    review = @website.transition_exclusions.active.sole
    patch distillator_transition_exclusion_path(review), params: { reason: "Source available again" }
    assert_redirected_to distillator_shadow_report_site_path(@website)
    assert review.reload.revoked_at
    assert_equal "Source available again", review.revocation_reason
    assert_equal 1, @website.transition_exclusions.count
    assert_includes Distillator::TransitionCheck.call(website: @website, check_options: { sample_mode: "all" }).representative_webpages.map(&:url), @gone.url
    follow_redirect!
    assert_select '#transition-exclusion-history:not([open])', text: /Restored.*Source available again/m
  end

  test "historical reports and pending checks do not offer exclusion controls" do
    Distillator::TransitionRun.request!(website: @website)
    get distillator_shadow_report_site_path(@website, run_id: @run.id)
    assert_select '#historical-transition-run'
    assert_select 'form[action="/distillator/transition_exclusions"]', count: 0
    get distillator_shadow_report_site_path(@website)
    assert_select 'form[action="/distillator/transition_exclusions"]', count: 0
    assert_no_difference "Distillator::TransitionExclusion.count" do
      post_review
    end
    assert_includes flash[:alert], "running transition check"
  end

  test "nine candidates become eight fresh comparisons and one reviewed exclusion without deleting stored data" do
    assert_equal 9, @website.webpages.publishable.count
    assert_not Distillator::RolloutTransition.call(website: @website, to_mode: "active").success?
    post_review
    review = @website.transition_exclusions.active.sole
    old_evidence = @run.transition_evidences.map(&:attributes)
    html = "<title>Event</title><address>Hall</address><time>2027-01-01</time>"
    results = @pages.to_h do |page|
      cache = Distillator::FetchCache.create!(uri_key: CGI.escape(page.url), normalized_url: page.url, html: html, body: html,
        headers: {}, http_response_code: 200, scrape_date: Time.current, successful_refresh: Time.current,
        signals: { transport_success: true, content_success: true, network_status: "ok" })
      [page.url, Distillator::FetchCacheStore::Result.new(cache: cache, cache_hit: false, body: html, signals: cache.signals)]
    end
    calls = []
    fetcher = Object.new
    fetcher.define_singleton_method(:fetch) { |uri:, **options| calls << options.merge(uri: uri); results.fetch(uri) }
    comparer = Object.new
    legacy_calls = []
    comparer.define_singleton_method(:call) do |uri:, **options|
      legacy_calls << options.merge(uri: uri)
      { legacy_cache: { html: results.fetch(uri).cache.html }, legacy_lookup_status: "ok", summary: {}, missing: {} }
    end
    exporter = Object.new
    %i[call production_equivalent].each do |method|
      exporter.define_singleton_method(method) { |**| '<https://example.org/event/1> <http://schema.org/name> "Event" .' }
    end
    checked = nil
    assert_no_difference ["Webpage.count", "Statement.count"] do
      checked = Distillator::TransitionCheckRunner.call(website: @website, check_options: { sample_mode: "all", strictness: "strict" },
        fetch_cache_store: fetcher, cache_compare: comparer, export_service: exporter)
    end
    new_run = @website.latest_completed_transition_run
    assert_equal 8, calls.length
    assert calls.all? { |call| call[:force_scrape] == true }
    assert_equal 8, legacy_calls.length
    assert legacy_calls.all? { |call| call[:fresh_legacy] == true }
    assert_not_includes calls.map { |call| call[:uri] }, @gone.url
    assert_equal %w[checked checked checked], checked.records.values.map(&:status)
    checked.records.values.each do |evidence|
      assert_equal 9, evidence.details["original_publishable_event_page_count"]
      assert_equal 8, evidence.details["publishable_event_page_count"]
      assert_equal 8, evidence.details["representative_webpage_count"]
      assert_equal [review.id], evidence.details["transition_exclusions"].map { |entry| entry["id"] }
    end
    assert_nil @website.transition_run_blocker
    assert_equal :ready, Distillator::TransitionStatus.for_completed_run(website: @website, run: new_run).status
    get distillator_shadow_report_site_path(@website, run_id: new_run.id)
    assert_response :success
    assert_select '.transition-decision h2', text: "Ready to activate — with reviewed exclusions"
    assert_select '#transition-exclusion-coverage', text: /9 original candidates.*8 compared.*1 excluded after review/m
    assert_select '#transition-reviewed-exclusions', text: /Source removed; verified manually/
    assert_select '#transition-reviewed-exclusions a[href*="run_id=' + @run.id.to_s + '"]'
    assert_equal old_evidence, @run.transition_evidences.map(&:attributes)

    activation = Distillator::RolloutTransition.call(website: @website, to_mode: "active")
    assert activation.success?, activation.errors.inspect
    assert_equal new_run.id, @website.rollout_events.last.readiness_snapshot["transition_run_id"]
    assert Distillator::RolloutTransition.call(website: @website, to_mode: "shadow").success?

    patch distillator_transition_exclusion_path(review), params: { reason: "Check this URL again" }
    assert_includes @website.transition_run_blocker, "configuration changed"
    assert_not Distillator::RolloutTransition.call(website: @website, to_mode: "active").success?
    get distillator_shadow_report_site_path(@website, run_id: new_run.id)
    assert_select '.transition-decision h2', text: "Scope or configuration changed — run a new check"
    assert_select '#transition-exclusion-coverage', text: /1 excluded after review/ # The completed run still records its original scope.
    assert_equal [review.id], new_run.transition_evidences.find_by!(check_kind: "fetch_parity").details["transition_exclusions"].map { |entry| entry["id"] }
    get distillator_shadow_report_site_path(@website, run_id: @run.id)
    assert_select '#transition-exclusion-coverage', count: 0
    assert_select '#transition-fetch-issues', text: /#{Regexp.escape(@gone.url)}/
  end

  test "excluding every publishable event cannot pass by falling back to a listing page" do
    @website.webpages.create!(url: "https://example.org/listing", rdf_uri: "rdf:listing", rdfs_class: rdfs_classes(:place))
    @pages.each do |page|
      run = publish_unavailable_source_run(@website, url: page.url)
      Distillator::TransitionExclusionReview.create!(website: @website, run: run, url: page.url, reason: "Source removed")
    end
    selection = Distillator::TransitionCheck.call(website: @website, check_options: { sample_mode: "all" })
    assert_equal 9, selection.original_publishable_event_page_count
    assert_equal 0, selection.publishable_event_page_count
    assert_empty selection.representative_webpages
    assert_equal 9, selection.transition_exclusions.length
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::TransitionCheckRunner.call(website: @website, check_options: { sample_mode: "all", strictness: "strict" })
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select '.transition-decision h2', text: "No eligible pages remain — stay in Shadow"
    assert_select '.transition-primary-action', text: "Restore a URL"
    assert_not_equal :ready, Distillator::TransitionStatus.call(website: @website).status
    assert_equal "shadow", @website.reload.distillator_mode
  end

  private

  def post_review(reason: "Source removed; verified manually", url: @gone.url)
    post distillator_transition_exclusions_path, params: { website_id: @website.id, source_run_id: @run.id, url: url, reason: reason }
  end
end
