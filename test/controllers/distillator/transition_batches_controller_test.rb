require "test_helper"

class Distillator::TransitionBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @one = site("culture-alpha", schedule: 1)
    @two = site("culture-beta", schedule: 0)
    @other = site("other-event", schedule: nil)
    @template = site("footlight-manual-fr")
    @test_site = site("culture-test")
    @place = site("culture-place", event: false)
  end
  teardown { ActiveJob::Base.queue_adapter = @old_adapter }

  test "culture wildcard selects matching event sites including unscheduled but excludes templates tests and entities" do
    get websites_path, params: { q: "culture*", graph_name: "https://example.org/culture", view: "all" }
    assert_response :success
    selected = Nokogiri::HTML(response.body).css('input[data-transition-site]').map { |input| input['value'].to_i }.sort
    assert_equal [@one.id, @two.id].sort, selected
    assert_select '#website-list-unscheduled input[data-transition-site][value="' + @two.id.to_s + '"]'
    assert_select 'input[data-transition-site][form="website-transition-batch"]', count: 2
    assert_select '[data-transition-master-label]', text: /Select all 2 matching event sites/
    assert_select '#website-transition-batch select[name=check_profile] option[value=thorough][selected]', 1
    assert_select '#website-transition-batch select[name=check_profile] option[value=light]', 1
    assert_select 'form form', count: 0
  end

  test "single selection opens the site workflow and group of one never renders a master report" do
    post distillator_transition_batches_path, params: params_for([@two.id])
    item = Distillator::SiteTransition.last
    assert_redirected_to distillator_site_transition_path(item)
    follow_redirect!
    assert_response :success
    assert_select 'h1', text: /culture-beta.*Transition workflow/
    assert_select 'a', text: "Group progress and results", count: 0
    assert_select '[data-workflow-follow]', count: 1
    assert_includes response.body, "Not enough previous timing data"
    get distillator_transition_batch_path(item.batch)
    assert_redirected_to distillator_site_transition_path(item)
    get distillator_transition_batches_path
    assert_response :success
    assert_select "a[href='#{distillator_site_transition_path(item)}']", text: "culture-beta"
    assert_select "a[href='#{distillator_transition_batch_path(item.batch)}']", count: 0
  end

  test "multiple selected sites have a master progress report and read only polling" do
    post distillator_transition_batches_path, params: params_for([@one.id, @two.id])
    batch = Distillator::TransitionBatch.last
    assert_redirected_to distillator_transition_batch_path(batch)
    follow_redirect!
    assert_select 'h1', text: /Event-site transition group/
    assert_select 'tr[data-workflow-result="queued"]', count: 2
    assert_includes response.body, "0/2 sites finished"
    assert_select '[data-workflow-filter]', count: 1
    assert_select 'input[type="submit"][value="Stop remaining sites"]'
    assert_no_difference ["Distillator::TransitionRun.count", "Distillator::SiteTransition.count", "Distillator::RolloutEvent.count"] do
      get distillator_transition_batch_path(batch, format: :json)
    end
    assert_response :success
    data = response.parsed_body
    assert_equal false, data["finished"]
    assert_includes data["html"], "0/2 sites finished"
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "legacy", @two.reload.distillator_mode
    patch distillator_transition_batch_path(batch)
    assert batch.site_transitions.reload.all? { |item| item.status == "cancelled" }
    assert_equal "legacy", @one.reload.distillator_mode
  end

  test "the group persists the chosen Light profile and rejects a different profile on replay" do
    parameters = params_for([@one.id, @two.id]).merge(check_profile: "light")
    post distillator_transition_batches_path, params: parameters
    batch = Distillator::TransitionBatch.last
    assert_redirected_to distillator_transition_batch_path(batch)
    assert_equal({ "sample_mode" => "default", "strictness" => "standard" }, batch.check_options)
    follow_redirect!
    assert_includes response.body, "Light · Default sample · Standard"

    assert_no_difference "Distillator::TransitionBatch.count" do
      post distillator_transition_batches_path, params: parameters.merge(check_profile: "thorough")
      assert_redirected_to websites_path
      assert_equal "This request belongs to a different check profile", flash[:alert]

      post distillator_transition_batches_path, params: params_for([@other.id]).merge(check_profile: "unknown")
      assert_redirected_to websites_path
      assert_equal "Choose Light or Thorough.", flash[:alert]
    end
  end

  test "Active audit is a separate Thorough request and rejects groups containing Shadow sites" do
    @one.update_column(:distillator_mode, "active")
    request = params_for([@one.id]).merge(workflow_action: "audit", check_profile: "light")
    get websites_path
    assert_select "button[data-transition-audit][name=workflow_action][value=audit]", text: "Audit selected Active sites (Thorough)"
    assert_select 'input[data-transition-mode="active"][value="' + @one.id.to_s + '"]'

    assert_no_difference "Distillator::TransitionBatch.count" do
      post distillator_transition_batches_path, params: params_for([@one.id, @two.id]).merge(workflow_action: "audit")
    end
    assert_redirected_to websites_path
    assert_equal "Select only Active event sites for an audit.", flash[:alert]

    post distillator_transition_batches_path, params: request
    batch = Distillator::TransitionBatch.last
    assert batch.audit?
    assert_equal "thorough", batch.check_profile
    follow_redirect!
    assert_includes response.body, "Active audit · Thorough"
    assert_select "li", text: /Thorough Active audit/
    assert_select "li", text: /Pre-activation comparison/, count: 0

    assert_no_difference "Distillator::TransitionBatch.count" do
      post distillator_transition_batches_path, params: request.merge(workflow_action: "validate", check_profile: "thorough")
    end
    assert_equal "This request belongs to a different workflow action", flash[:alert]
  end

  test "batch diagnostics are unavailable while any site is unfinished" do
    post distillator_transition_batches_path, params: params_for([@one.id, @two.id])
    batch = Distillator::TransitionBatch.last
    get distillator_transition_batch_path(batch, format: :json)
    assert_not_includes response.parsed_body.fetch("html"), "Export diagnostics"

    get diagnostics_distillator_transition_batch_path(batch, format: :json)
    assert_response :conflict
    assert_includes response.parsed_body.fetch("error"), "still running"
  end

  test "completed group exports capped examples by site and error kind from its recorded runs" do
    post distillator_transition_batches_path, params: params_for([@one.id, @two.id]).merge(check_profile: "light")
    batch = Distillator::TransitionBatch.last
    first, second = batch.site_transitions.order(:position).to_a
    pre = diagnostic_run(@one)
    post = diagnostic_run(@one, status: "failed", error_message: "The worker stopped before the transition check finished.")
    other = diagnostic_run(@two)
    unrelated = diagnostic_run(@one)
    failure = ->(url, code) { { url: url, fetch_status: "failed", http_response_code: code, fetch_reason: "http_#{code}" } }
    urls = (1..4).map { |i| "https://example.org/event-#{i}" }
    rows = urls.map { |url| failure.call(url, 404) } + [failure.call(urls.first, 410)]
    rows << { url: urls.last, fetch_status: "passed", legacy_lookup_status: "unreachable",
      legacy_fetch: { upstream_http_code: 429 }, legacy_lookup_error: "Wringer scrape was rate limited" }
    rows << { url: urls[2], fetch_status: "passed", legacy_lookup_status: "ok", comparison_status: "failed",
      compare_summary: { blocking_regressions: ["final_url"] } }
    diagnostic_evidence(pre, "fetch_parity", representative_url_results: rows)
    diagnostic_evidence(unrelated, "fetch_parity", representative_url_results: [failure.call("https://example.org/unrelated", 500)])
    diagnostic_evidence(other, "fetch_parity", representative_url_results: [failure.call(urls.first, 404)])
    missing = { verdict: "MISSING_STATEMENT", core_field: true, legacy: nil, condenser: nil, property_label: "Location", source_id: 1945 }
    diagnostic_evidence(pre, "statement_delta", statement_artifacts: urls.map { |url| missing.merge(webpage_url: url) })
    diagnostic_evidence(pre, "export_diff", reason: "export_generation_failed",
      error_class: "JsonldGenerator::EventSeriesConversionError", error_message: "Ambiguous venues")
    historical_error = "Invalid URL: https://phantomjscloud.com/api/browser/v2/test-renderer-secret/?request=fixture"
    first.update!(status: "attention", phase: "finished", pre_run: pre, post_run: post, completed_at: Time.current, reason: historical_error)
    second.update!(status: "attention", phase: "finished", pre_run: other, completed_at: Time.current)

    get distillator_transition_batch_path(batch, format: :json)
    assert response.parsed_body.fetch("finished")
    assert_includes response.parsed_body.fetch("html"), "Export diagnostics (JSON)"

    assert_no_difference ["Distillator::TransitionRun.count", "Distillator::TransitionEvidence.count", "Distillator::RolloutEvent.count"] do
      get diagnostics_distillator_transition_batch_path(batch, format: :json)
    end
    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_includes response.headers["Content-Disposition"], "transition-group-#{batch.id}-diagnostics.json"
    assert_not_includes response.body, "test-renderer-secret"
    assert_not_includes response.body, "unrelated"
    report = response.parsed_body
    assert_equal "light", report["check_profile"]
    assert_equal({ "attention" => 2 }, report["status_counts"])
    alpha, beta = report.fetch("sites")
    issues = alpha.fetch("issues").index_by { |issue| issue["code"] }
    assert_equal [pre.id, post.id], alpha.fetch("checks").pluck("run_id")
    assert_equal 4, issues.fetch("http_404").fetch("recorded_occurrences")
    assert_equal urls.first(2), issues.fetch("http_404").fetch("examples").pluck("url")
    assert_equal 1, issues.fetch("http_410").fetch("examples").size
    assert_equal ["Wringer"], issues.fetch("http_429").fetch("examples").pluck("backend")
    assert_equal ["final_url"], issues.fetch("cache_comparison_failed").fetch("examples").first.fetch("fields")
    assert_equal [1945, 1945], issues.fetch("shared_missing_required_field").fetch("examples").pluck("source_id")
    assert_equal ["Ambiguous venues"], issues.fetch("export_generation_failed").fetch("examples").pluck("message")
    assert_equal ["postcheck"], issues.fetch("run_failed").fetch("examples").pluck("phase")
    assert_equal 1, beta.fetch("issues").first.fetch("recorded_occurrences")
  end

  test "empty selection and forged excluded sites never queue a workflow" do
    [[], [@template.id], [@test_site.id], [@place.id]].each do |ids|
      assert_no_difference ["Distillator::TransitionBatch.count", "Distillator::SiteTransition.count", "Distillator::RolloutEvent.count"] do
        post distillator_transition_batches_path, params: params_for(ids)
      end
      assert_redirected_to websites_path
      assert flash[:alert].present?
    end
  end

  test "the group can request cancellation of its running site independently of queued sites" do
    post distillator_transition_batches_path, params: params_for([@one.id, @two.id])
    batch = Distillator::TransitionBatch.last
    current, queued = batch.site_transitions.order(:position).to_a
    current.update!(status: "running", phase: "precheck", phase_token: SecureRandom.hex, started_at: Time.current)

    get distillator_transition_batch_path(batch)
    assert_select "input[type=submit][value='Cancel current transition']", 1
    assert_select "input[type=submit][value='Stop remaining sites']", 1
    patch cancel_distillator_site_transition_path(queued)
    assert_nil queued.reload.cancel_requested_at

    patch cancel_distillator_site_transition_path(current), params: { from: "batch" }
    assert_redirected_to distillator_transition_batch_path(batch)
    requested_at = current.reload.cancel_requested_at
    assert requested_at
    assert_equal "running", current.status
    assert_equal "queued", queued.reload.status
    assert_nil batch.reload.stopped_at

    patch cancel_distillator_site_transition_path(current)
    assert_equal requested_at, current.reload.cancel_requested_at
    get distillator_site_transition_path(current)
    assert_includes response.body, "Cancellation requested. The current operation may need to finish"
    assert_select "input[type=submit][value='Cancel current transition']", 0
  end

  test "successful site report has one verdict and links both checks without empty findings" do
    post distillator_transition_batches_path, params: params_for([@one.id])
    item = Distillator::SiteTransition.last
    runs = 2.times.map do
      @one.transition_runs.create!(status: "completed", requested_at: 2.minutes.ago, completed_at: Time.current,
        configuration_digest: Distillator::TransitionFingerprint.call(@one))
    end
    ready = { state: "ready", fetch: "passed", statements: "passed", export: "passed", warnings: [], blockers: [] }
    item.update!(status: "passed", phase: "finished", pre_run: runs[0], post_run: runs[1], final_mode: "active", final_backend: "condenser",
      phase_results: { precheck: ready, postcheck: ready })
    get distillator_site_transition_path(item)
    assert_response :success
    assert_select "h2", text: "Passed"
    assert_select "details[id$='-findings']", count: 0
    assert_includes response.body, "Pre-activation verification passed."
    assert_includes response.body, "Active verification passed."
    runs.each do |run|
      assert_select "a[href='#{distillator_shadow_report_site_path(@one.id, run_id: run.id)}']", minimum: 1
    end
    item.update!(status: "attention", phase_results: { postcheck: ready.merge(state: "blocked", statements: "failed", blockers: ["Title differs"]) })
    get distillator_site_transition_path(item, format: :json)
    html = Nokogiri::HTML(response.parsed_body.fetch("html"))
    assert_equal 1, html.css("details[open]").length
    assert_includes html.text, "Title differs"
  end

  test "group results show one attention label and pin challenge inspection to the failed run" do
    post distillator_transition_batches_path, params: params_for([@one.id, @two.id])
    batch = Distillator::TransitionBatch.last
    item = batch.site_transitions.order(:position).first
    run = @one.transition_runs.create!(status: "completed", requested_at: 1.minute.ago, completed_at: Time.current,
      configuration_digest: Distillator::TransitionFingerprint.call(@one))
    item.update!(status: "attention", phase: "finished", pre_run: run, final_mode: "shadow", final_backend: "wringer",
      reason: "Condenser: system_cloudflare; cloudflare; system_captcha; captcha — https://example.org/event")
    get distillator_transition_batch_path(batch)
    assert_response :success
    assert_select 'tr[data-workflow-result="attention"]' do
      assert_select 'td:nth-child(2)', text: "AttentionNot started"
      assert_select 'p', text: /Condenser reported a Cloudflare\/CAPTCHA challenge/
      assert_select 'a', text: "Inspect recorded failure", href: distillator_shadow_report_site_path(@one.id, run_id: run.id, anchor: "transition-fetch-issues")
      assert_select 'details', text: /system_cloudflare/
    end
  end

  test "run page processing progress and history based estimate are visible without claiming parity" do
    started = 1.hour.ago
    run = @one.transition_runs.create!(status: "completed", requested_at: started, started_at: started,
      completed_at: started + 30.seconds, configuration_digest: Distillator::TransitionFingerprint.call(@one))
    run.transition_evidences.create!(website: @one, url: @one.webpages.first.url, check_kind: "fetch_parity", status: "checked",
      checked_at: run.completed_at, details: { representative_webpage_count: 1 })
    source = @one.sources.create!(property: properties(:four), selected: true, language: "en", algorithm_value: "manual=Title")
    [properties(:four), properties(:location), properties(:six)].each do |property|
      current = property == properties(:four) ? source : @one.sources.create!(property: property, selected: true, language: "en", algorithm_value: "manual=Value")
      Statement.create!(webpage: @one.webpages.first, source: current, cache: "2027-01-01", status: "ok")
    end
    Statement.where(webpage: @one.webpages.first).update_all(status: "ok")
    assert_equal 60, Distillator::TransitionTimeEstimate.for_site(@one)
    assert_nil Distillator::TransitionTimeEstimate.for_sites([@one, @two])[@two.id]
    post distillator_transition_batches_path, params: params_for([@one.id])
    item = Distillator::SiteTransition.last
    @one.update_column(:distillator_mode, "shadow")
    item.update!(status: "running", phase: "precheck", started_at: Time.current, phase_started_at: Time.current,
      estimated_seconds: 60, expected_mode: "shadow")
    working = Distillator::TransitionRun.request!(website: @one, workflow_item: item).run
    working.update!(status: "running", started_at: Time.current)
    working.record_progress!("fetch", completed: 3, total: 9)
    item.update!(pre_run: working)
    get distillator_site_transition_path(item, format: :json)
    assert_response :success
    assert_includes response.parsed_body["html"], "3/9 pages processed"
    assert_includes response.parsed_body["html"], "based on previous checks"
    assert_equal false, response.parsed_body["finished"]
    assert_no_match /ready to activate/i, response.parsed_body["html"]
  end

  private

  def diagnostic_run(website, status: "completed", error_message: nil)
    website.transition_runs.create!(status: status, requested_at: 1.minute.ago, completed_at: Time.current,
      configuration_digest: Distillator::TransitionFingerprint.call(website), error_message: error_message)
  end

  def diagnostic_evidence(run, kind, **details)
    run.transition_evidences.create!(website: run.website, url: run.website.webpages.first.url, check_kind: kind,
      status: "failed", checked_at: run.completed_at, details: details)
  end

  def site(seed, schedule: 1, event: true)
    website = Website.create!(name: seed, seedurl: seed, graph_name: "https://example.org/#{seed}", default_language: "en", schedule_every_days: schedule, distillator_mode: "legacy")
    website.webpages.create!(url: "https://example.org/#{seed}", rdf_uri: "rdf:#{seed}", rdfs_class: event ? rdfs_classes(:one) : rdfs_classes(:place))
    website
  end

  def params_for(ids)
    { website_ids: ids.map(&:to_s), request_key: SecureRandom.uuid, selection_context: "q: culture*" }
  end
end
