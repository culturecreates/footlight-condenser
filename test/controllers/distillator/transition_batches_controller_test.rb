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

  test "empty selection and forged excluded sites never queue a workflow" do
    [[], [@template.id], [@test_site.id], [@place.id]].each do |ids|
      assert_no_difference ["Distillator::TransitionBatch.count", "Distillator::SiteTransition.count", "Distillator::RolloutEvent.count"] do
        post distillator_transition_batches_path, params: params_for(ids)
      end
      assert_redirected_to websites_path
      assert flash[:alert].present?
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

  def site(seed, schedule: 1, event: true)
    website = Website.create!(name: seed, seedurl: seed, graph_name: "https://example.org/#{seed}", default_language: "en", schedule_every_days: schedule, distillator_mode: "legacy")
    website.webpages.create!(url: "https://example.org/#{seed}", rdf_uri: "rdf:#{seed}", rdfs_class: event ? rdfs_classes(:one) : rdfs_classes(:place))
    website
  end

  def params_for(ids)
    { website_ids: ids.map(&:to_s), request_key: SecureRandom.uuid, selection_context: "q: culture*" }
  end
end
