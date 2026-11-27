require "test_helper"

class Distillator::SiteTransitionProcessorTest < ActiveSupport::TestCase
  class Runner
    attr_accessor :pre_failure, :post_failure, :callback
    attr_reader :calls
    def initialize
      @calls = []
    end
    def call(website:, transition_run:, verify_active_path:, require_native_path:, cancellation_check: nil)
      @calls << { website_id: website.id, active_path: verify_active_path, mode: website.distillator_mode, native_required: require_native_path }
      callback&.call(website, verify_active_path)
      cancellation_check&.call
      failed = verify_active_path ? post_failure : pre_failure
      urls = website.webpages.pluck(:url)
      %w[fetch_parity statement_delta export_diff].each do |kind|
        details = { fetch_basis: "fresh_both", representative_webpages: urls, representative_webpage_count: urls.length,
          reason: failed ? "strict_statement_parity_failed" : "ok", active_path_verification: verify_active_path }
        transition_run.transition_evidences.create!(website: website, url: urls.first, check_kind: kind,
          status: failed && kind == "statement_delta" ? "failed" : "checked", checked_at: Time.current,
          statement_count_delta_acceptable: !failed, export_diff_checked: true, details: details)
      end
    end
  end

  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @website = create_site("pilot")
    @runner = Runner.new
    @processor = Distillator::SiteTransitionProcessor.new(runner: @runner)
  end
  teardown { ActiveJob::Base.queue_adapter = @old_adapter }

  test "Legacy moves through Shadow and Active with distinct pre and ordinary active checks" do
    batch, item = request
    assert_equal "legacy", @website.reload.distillator_mode
    @processor.perform(item.id, phase: "queued")
    assert_equal "active", @website.reload.distillator_mode
    assert_equal "postcheck", item.reload.phase
    assert_equal "completed", item.pre_run.status
    assert_equal({ "sample_mode" => "all", "strictness" => "strict" }, item.pre_run.check_options)
    assert_nil item.post_run
    @processor.perform(item.id, phase: "postcheck")
    assert_equal "passed", item.reload.status
    assert_equal "active", item.final_mode
    assert_equal "condenser", item.final_backend
    assert_equal "completed", item.post_run.status
    assert_not_equal item.pre_run_id, item.post_run_id
    assert_equal [false, true], @runner.calls.map { |call| call[:active_path] }
    assert @runner.calls.all? { |call| call[:native_required] }
    assert_equal %w[shadow active], @runner.calls.map { |call| call[:mode] }
    assert_equal %w[legacy shadow], @website.rollout_events.order(:id).pluck(:from_mode)
    assert_equal "ready", item.phase_results.dig("postcheck", "state")
    assert_no_difference ["Distillator::TransitionRun.count", "Distillator::RolloutEvent.count"] do
      @processor.perform(item.id, phase: "postcheck")
      @processor.perform(item.id, phase: "queued")
      Distillator::SiteTransitionWatchdogJob.perform_now(item.id)
    end
    assert batch.site_transitions.all?(&:terminal?)
  end

  test "a failed precheck stays Shadow and reports what passed and failed" do
    _, item = request
    @runner.pre_failure = true
    @processor.perform(item.id, phase: "queued")
    assert_equal "attention", item.reload.status
    assert_equal "shadow", @website.reload.distillator_mode
    assert_equal "wringer", item.final_backend
    assert_equal "blocked", item.phase_results.dig("precheck", "state")
    assert_equal "passed", item.phase_results.dig("precheck", "fetch")
    assert_equal "failed", item.phase_results.dig("precheck", "statements")
    assert_equal "passed", item.phase_results.dig("precheck", "export")
    assert_nil item.post_run
    assert_equal 0, @website.rollout_events.where(to_mode: "active").count
  end

  test "cancelling a running site stops its work and keeps the rest of the group eligible" do
    other = create_site("after-cancel")
    batch = Distillator::TransitionBatch.request!(website_ids: [@website.id, other.id], request_key: SecureRandom.uuid)
    first, second = batch.site_transitions.order(:position).to_a
    @runner.callback = ->(_, _) { first.reload.request_cancellation! }

    @processor.perform(first.id, phase: "queued")

    assert_equal "cancelled", first.reload.status
    assert_equal "failed", first.pre_run.status
    assert_equal Distillator::TransitionRun::CANCELLED_MESSAGE, first.pre_run.error_message
    assert_empty first.pre_run.transition_evidences
    assert_equal "shadow", @website.reload.distillator_mode
    assert_nil batch.reload.stopped_at
    assert_equal "queued", second.reload.status

    @runner.callback = nil
    @processor.perform(second.id, phase: "queued")
    assert_equal "postcheck", second.reload.phase
  end

  test "cancelling between checks recovers Shadow before creating the Active check" do
    _, item = request
    @processor.perform(item.id, phase: "queued")
    assert_equal "active", @website.reload.distillator_mode
    assert item.reload.request_cancellation!

    assert_no_difference "Distillator::TransitionRun.count" do
      @processor.perform(item.id, phase: "postcheck")
    end

    assert_equal "cancelled", item.reload.status
    assert_equal "completed", item.pre_run.status
    assert_equal "completed", item.phase_results.dig("recovery", "state")
    assert_equal "shadow", @website.reload.distillator_mode
  end

  test "Light runs the same sampled Standard profile in precheck and Active verification" do
    batch = Distillator::TransitionBatch.request!(website_ids: [@website.id], request_key: SecureRandom.uuid, check_profile: "light")
    item = batch.site_transitions.sole

    @processor.perform(item.id, phase: "queued")
    @processor.perform(item.id, phase: "postcheck")

    assert_equal "passed", item.reload.status
    assert_equal batch.check_options, item.pre_run.check_options
    assert_equal batch.check_options, item.post_run.check_options
    assert_equal "default", item.post_run.options.sample_mode
    refute item.post_run.options.strict?
  end

  test "an interrupted Migrated workflow keeps serving through Condenser" do
    @website.update!(distillator_mode: "active")
    Distillator::VerifiedCutover.confirm!(website: @website, completed_at: Time.current, actor: "operator",
      evidence: "Production handoff confirmed")
    @runner.callback = ->(*) { raise "Worker interrupted" }
    _, item = request

    assert_no_difference "Distillator::RolloutEvent.count" do
      @processor.perform(item.id, phase: "queued")
    end

    assert_equal "attention", item.reload.status
    assert_nil item.pre_run
    assert_equal "failed", item.post_run.status
    assert_equal "not_needed", item.phase_results.dig("recovery", "state")
    assert_equal "active", @website.reload.distillator_mode
  end

  test "failed active verification returns to Shadow and preserves both reports" do
    _, item = request
    @runner.post_failure = true
    @processor.perform(item.id, phase: "queued")
    @processor.perform(item.id, phase: "postcheck")
    assert_equal "attention", item.reload.status
    assert_equal "shadow", item.final_mode
    assert_equal "shadow", @website.reload.distillator_mode
    assert_equal "ready", item.phase_results.dig("precheck", "state")
    assert_equal "blocked", item.phase_results.dig("postcheck", "state")
    assert_equal "completed", item.phase_results.dig("recovery", "state")
    assert_equal "active", @website.rollout_events.order(:id).last.from_mode
  end

  test "Thorough validation sends an already Active site through Shadow first and recovers if Active verification fails" do
    @website.update_column(:distillator_mode, "active")
    _, item = request
    @runner.post_failure = true

    @processor.perform(item.id, phase: "queued")
    assert_equal "active", @website.reload.distillator_mode
    assert_equal "ready", item.reload.phase_results.dig("precheck", "state")
    assert_equal "strict", item.pre_run.options.strictness
    assert_equal "all", item.pre_run.options.sample_mode
    assert item.pre_run.refresh_discovery?
    assert_nil item.post_run

    @processor.perform(item.id, phase: "postcheck")
    assert_equal "attention", item.reload.status
    assert_equal item.pre_run.check_options, item.post_run.check_options
    assert_not item.post_run.refresh_discovery?
    assert_equal %w[shadow active], @runner.calls.pluck(:mode)
    assert_equal [false, true], @runner.calls.pluck(:active_path)
    assert_equal %w[shadow active shadow], @website.rollout_events.order(:id).pluck(:to_mode)
    assert_equal "shadow", item.final_mode
  end

  test "Thorough validation stays in Shadow if a previously Active site fails the precheck" do
    @website.update_column(:distillator_mode, "active")
    _, item = request
    @runner.pre_failure = true

    @processor.perform(item.id, phase: "queued")

    assert_equal "attention", item.reload.status
    assert_equal "shadow", @website.reload.distillator_mode
    assert_equal %w[shadow], @website.rollout_events.order(:id).pluck(:to_mode)
    assert_nil item.post_run
  end

  test "existing workflows preserve their verification behavior for an already Active site" do
    @website.update_column(:distillator_mode, "active")
    batch, item = request
    batch.update_column(:workflow_action, "verify")
    @runner.post_failure = true

    @processor.perform(item.id, phase: "queued")

    assert_nil item.reload.pre_run
    assert_equal [true], @runner.calls.map { |call| call[:active_path] }
    assert_equal "shadow", @website.reload.distillator_mode
  end

  test "Active audit captures Thorough verification failures without changing rollout mode" do
    @website.update_column(:distillator_mode, "active")
    _, item = request(workflow_action: "audit", check_profile: "light")
    @runner.post_failure = true

    assert_no_difference "Distillator::RolloutEvent.count" do
      @processor.perform(item.id, phase: "queued")
    end

    assert_equal [true], @runner.calls.pluck(:active_path)
    assert_nil item.reload.pre_run
    assert_equal "all", item.post_run.options.sample_mode
    assert item.post_run.options.strict?
    assert_not item.post_run.options.include_retired?
    assert_not item.post_run.refresh_discovery?
    assert_equal "blocked", item.phase_results.dig("postcheck", "state")
    assert_equal "attention", item.status
    assert_equal "active", item.final_mode
    assert_equal "active", @website.reload.distillator_mode
  end

  test "an Active site with only archived publishable events stays Active" do
    @website.update_column(:distillator_mode, "active")
    @website.webpages.sole.update_column(:archive_date, 1.day.ago)
    _, item = request

    assert_no_difference ["Distillator::TransitionRun.count", "Distillator::RolloutEvent.count"] do
      @processor.perform(item.id, phase: "queued")
    end

    assert_equal "attention", item.reload.status
    assert_equal "active", @website.reload.distillator_mode
    assert_includes item.reason, "No active publishable event pages"
    assert_empty @runner.calls
  end

  test "an Active audit timeout records the failure without rolling back the website" do
    @website.update_column(:distillator_mode, "active")
    _, item = request(workflow_action: "audit")
    @processor.send(:claim, item, "queued")
    item.reload.update!(deadline_at: 1.minute.ago)

    assert_no_difference "Distillator::RolloutEvent.count" do
      Distillator::SiteTransitionWatchdogJob.perform_now(item.id)
    end

    assert_equal "attention", item.reload.status
    assert_equal "failed", item.post_run.status
    assert_equal "active", @website.reload.distillator_mode
    assert_equal "active", item.final_mode
  end

  test "a dead worker after activation is recovered and late jobs cannot reactivate" do
    _, item = request
    @processor.perform(item.id, phase: "queued")
    assert_equal "active", @website.reload.distillator_mode
    item.update!(deadline_at: 1.minute.ago)
    Distillator::SiteTransitionWatchdogJob.perform_now(item.id)
    assert_equal "attention", item.reload.status
    assert_equal "shadow", @website.reload.distillator_mode
    assert_no_difference "Distillator::RolloutEvent.count" do
      @processor.perform(item.id, phase: "postcheck")
    end
  end

  test "a dead worker comparing the Active path rolls back before the workflow deadline" do
    _, item = request
    @processor.perform(item.id, phase: "queued")
    assert_equal "active", @website.reload.distillator_mode
    @processor.send(:claim, item, "postcheck")
    run = item.reload.post_run
    run.update!(status: "running", started_at: Time.current, progress: { execution_lock: true })
    assert_operator item.deadline_at, :>, 1.minute.from_now

    Distillator::TransitionBatchReconcileJob.perform_now

    assert_equal "failed", run.reload.status
    assert_equal "attention", item.reload.status
    assert_equal "failed", item.phase_results.dig("postcheck", "state")
    assert_equal "shadow", @website.reload.distillator_mode
    assert_equal "completed", item.phase_results.dig("recovery", "state")
  end

  test "a paused Active verification continues the same run after worker interruption" do
    _, item = request
    @processor.perform(item.id, phase: "queued")
    paused_runner = Object.new
    def paused_runner.call(**) = Distillator::TransitionRun::CONTINUE
    Distillator::SiteTransitionProcessor.new(runner: paused_runner).perform(item.id, phase: "postcheck")
    run = item.reload.post_run
    assert_equal "running", run.status
    assert_equal "active", @website.reload.distillator_mode
    assert_empty run.transition_evidences

    Distillator::SiteTransitionJob.expects(:perform_later).with(item.id, phase: "postcheck").returns(true)
    Distillator::TransitionBatchReconcileJob.perform_now
    @processor.perform(item.id, phase: "postcheck")

    assert_equal run.id, item.reload.post_run_id
    assert_equal "completed", run.reload.status
    assert_equal "passed", item.status
    assert_equal "active", @website.reload.distillator_mode
  end

  test "the sweep restores the Active check dispatch if the worker disappears between checks" do
    _, item = request
    @processor.perform(item.id, phase: "queued")
    assert_equal "completed", item.reload.pre_run.status
    assert_equal "active", @website.reload.distillator_mode
    assert_nil item.post_run_id
    Distillator::SiteTransitionJob.expects(:perform_later).with(item.id, phase: "postcheck").returns(true)
    Distillator::TransitionBatchReconcileJob.perform_now

    replacement = Runner.new
    Distillator::SiteTransitionProcessor.new(runner: replacement).perform(item.id, phase: "postcheck")
    assert_equal [{ website_id: @website.id, active_path: true, mode: "active", native_required: true }], replacement.calls
    assert_equal "passed", item.reload.status
    assert_equal "completed", item.post_run.status
  end

  test "manual rollback wins over automation even while a check is executing" do
    _, item = request
    @processor.perform(item.id, phase: "queued")
    @runner.callback = ->(website, _) { Distillator::RolloutTransition.call(website: website, to_mode: "legacy", reason: "Operator intervention") }
    @processor.perform(item.id, phase: "postcheck")
    assert_equal "cancelled", item.reload.status
    assert_equal "legacy", @website.reload.distillator_mode
    assert_equal "legacy", item.final_mode
    assert_includes item.reason, "operator changed"
  end

  test "configuration changes cannot authorize activation" do
    _, item = request
    @runner.callback = ->(website, _) { website.update!(default_language: "fr") }
    @processor.perform(item.id, phase: "queued")
    assert_equal "attention", item.reload.status
    assert_equal "shadow", @website.reload.distillator_mode
    assert_equal "failed", item.pre_run.status
  end

  test "a postcheck queue failure triggers recovery rather than leaving unverified Active" do
    _, item = request
    Distillator::SiteTransitionJob.expects(:perform_later).with(item.id, phase: "postcheck").returns(false)
    @processor.perform(item.id, phase: "queued")
    assert_equal "attention", item.reload.status
    assert_equal "shadow", @website.reload.distillator_mode
    assert_includes item.reason, "queue active-path"
  end

  test "a failed recovery is reported as failure with the actual Active state" do
    _, item = request
    @processor.perform(item.id, phase: "queued")
    @runner.post_failure = true
    rollout = Object.new
    rollout.define_singleton_method(:call) do |**args|
      if args[:to_mode] == "shadow"
        Distillator::RolloutTransition::Result.new(success?: false, errors: ["Cannot save mode"])
      else
        Distillator::RolloutTransition.call(**args)
      end
    end
    Distillator::SiteTransitionProcessor.new(runner: @runner, rollout: rollout).perform(item.id, phase: "postcheck")
    assert_equal "recovery_failed", item.reload.status
    assert_equal "active", item.final_mode
    assert_equal "active", @website.reload.distillator_mode
    assert_includes item.reason, "Recovery failed"
  end

  test "an exception in active verification recovers without publishing partial evidence" do
    _, item = request
    @processor.perform(item.id, phase: "queued")
    @runner.callback = ->(_, _) { raise "Network connection failed" }
    @processor.perform(item.id, phase: "postcheck")
    assert_equal "attention", item.reload.status
    assert_equal "failed", item.post_run.status
    assert_equal "shadow", @website.reload.distillator_mode
    assert_includes item.reason, "Network connection failed"
  end

  test "duplicate selections reuse the group and overlapping groups are rejected atomically" do
    key = SecureRandom.uuid
    batch = Distillator::TransitionBatch.request!(website_ids: [@website.id.to_s], request_key: key)
    assert_no_difference ["Distillator::TransitionBatch.count", "Distillator::SiteTransition.count"] do
      assert_equal batch.id, Distillator::TransitionBatch.request!(website_ids: [@website.id.to_s], request_key: key).id
    end
    other = create_site("other")
    assert_raises(ArgumentError) do
      Distillator::TransitionBatch.request!(website_ids: [@website.id, other.id], request_key: SecureRandom.uuid)
    end
    assert_equal "legacy", other.reload.distillator_mode
    assert_raises(Distillator::TransitionRun::WorkflowBusy) { Distillator::TransitionRun.request!(website: @website) }
  end

  test "the group continues after a failure and stop remaining does not interrupt the current site" do
    other = create_site("other")
    batch = Distillator::TransitionBatch.request!(website_ids: [@website.id, other.id], request_key: SecureRandom.uuid)
    first, second = batch.site_transitions.order(:position).to_a
    @runner.pre_failure = true
    @processor.perform(first.id, phase: "queued")
    assert_equal "attention", first.reload.status
    assert_equal "queued", second.reload.status
    @runner.pre_failure = false
    @processor.perform(second.id, phase: "queued")
    batch.stop_remaining!
    @processor.perform(second.id, phase: "postcheck")
    assert_equal "passed", second.reload.status
    assert_equal "active", other.reload.distillator_mode
  end

  test "queued duplicate jobs cannot start another site while the group has running work" do
    other = create_site("sequential-other")
    batch = Distillator::TransitionBatch.request!(website_ids: [@website.id, other.id], request_key: SecureRandom.uuid)
    first, second = batch.site_transitions.order(:position).to_a
    @runner.callback = ->(_, _) { @processor.perform(second.id, phase: "queued") }
    @processor.perform(first.id, phase: "queued")
    assert_equal "running", first.reload.status
    assert_equal "queued", second.reload.status
    assert_equal "legacy", other.reload.distillator_mode
    assert_nil second.pre_run
  end

  test "a mixed three-site group records a pass a failure and a successful revalidation" do
    other = create_site("mixed-attention")
    active = create_site("mixed-active")
    active.update_column(:distillator_mode, "active")
    batch = Distillator::TransitionBatch.request!(website_ids: [@website.id, other.id, active.id], request_key: SecureRandom.uuid)
    first, second, third = batch.site_transitions.order(:position).to_a
    @processor.perform(first.id, phase: "queued")
    @processor.perform(first.id, phase: "postcheck")
    @runner.pre_failure = true
    @processor.perform(second.id, phase: "queued")
    @runner.pre_failure = false
    @processor.perform(third.id, phase: "queued")
    @processor.perform(third.id, phase: "postcheck")
    assert_equal %w[passed attention passed], batch.site_transitions.order(:position).pluck(:status)
    assert_equal %w[active shadow active], batch.site_transitions.order(:position).pluck(:final_mode)
    assert_equal "completed", third.reload.pre_run.status
    assert_equal "completed", third.post_run.status
    assert_equal 3, batch.site_transitions.count
  end

  test "expired queued and running standalone checks no longer block admission" do
    %w[queued running].each do |state|
      site = create_site("expired-#{state}")
      run = Distillator::TransitionRun.request!(website: site).run
      run.update!(status: state, requested_at: 2.hours.ago)
      batch = Distillator::TransitionBatch.request!(website_ids: [site.id], request_key: SecureRandom.uuid)
      assert_equal site.id, batch.site_transitions.sole.website_id
      assert_equal "failed", run.reload.status
      assert run.completed_at
      assert_includes run.error_message, "expired"
      executed = false
      run.execute { executed = true }
      assert_not executed, "An expired worker must not publish or execute a replacement check"
    end
  end

  test "admission respects the exact lease boundary and preserves healthy standalone checks" do
    travel_to Time.current.change(usec: 0) do
      run = Distillator::TransitionRun.request!(website: @website).run
      run.update!(requested_at: Time.current - Distillator::TransitionRun::LEASE + 1.second)
      assert_raises(ArgumentError) { request }
      assert_equal "queued", run.reload.status
      run.update!(requested_at: Time.current - Distillator::TransitionRun::LEASE)
      assert_difference "Distillator::TransitionBatch.count", 1 do
        request
      end
      assert_equal "failed", run.reload.status
    end
  end

  test "an expired workflow-owned run cannot be bypassed by a new selection" do
    _, item = request
    @processor.send(:claim, item, "queued")
    run = item.reload.pre_run
    run.update!(requested_at: 2.hours.ago, status: "running")
    assert_raises(ArgumentError) { request }
    assert_equal "running", run.reload.status
    assert_equal "running", item.reload.status
  end

  test "periodic recovery covers a crash before the per-site guard was enqueued" do
    _, item = request
    @processor.send(:claim, item, "queued")
    item.update!(deadline_at: 1.minute.ago)
    Distillator::TransitionBatchReconcileJob.perform_now
    Distillator::SiteTransitionWatchdogJob.perform_now(item.id)
    assert_equal "attention", item.reload.status
    assert_equal "failed", item.pre_run.status
    assert_equal "shadow", @website.reload.distillator_mode
  end

  test "a failed normal enqueue leaves committed selection available to the sweep" do
    Distillator::SiteTransitionJob.expects(:perform_later).returns(false)
    batch, item = request
    assert_nil batch.stopped_at
    assert_equal "queued", item.status
    Distillator::SiteTransitionJob.unstub(:perform_later)
    Distillator::TransitionBatchReconcileJob.perform_now
    assert batch.reload.last_reconciled_at
    assert_equal "queued", item.reload.status
  end

  test "template test and entity sites are rejected including forged selections" do
    %w[footlight-manual-fr pilot-test pilot-place].each do |seed|
      site = create_site(seed)
      assert_raises(ArgumentError) { Distillator::TransitionBatch.request!(website_ids: [site.id], request_key: SecureRandom.uuid) }
      assert_equal "legacy", site.reload.distillator_mode
    end
  end

  test "unscheduled event sites are eligible and deleted sites retain a group result" do
    @website.update!(schedule_every_days: nil)
    batch, item = request
    @website.destroy!
    @processor.perform(item.id, phase: "queued")
    assert_equal "cancelled", item.reload.status
    assert_equal "Website was deleted", item.reason
    assert_equal "pilot", item.website_name
    assert_equal 1, batch.site_transitions.count
  end

  test "full workflow uses real selected-source extraction and switches from forced precheck to ordinary Active dispatch" do
    page = @website.webpages.sole
    @website.sources.destroy_all
    archived = @website.webpages.create!(url: "https://example.org/vibration90-2026", language: "en", rdf_uri: "rdf:archived",
      rdfs_class: rdfs_classes(:one), archive_date: 1.day.ago)
    { "Title" => "title", "Location" => "address", "Dates" => "time" }.each do |label, tag|
      property = Property.create!(label: label, uri: "https://example.org/property/#{label}", value_datatype: "MyString", rdfs_class: rdfs_classes(:one))
      source = @website.sources.create!(property: property, language: "en", selected: true, algorithm_value: "xpath=//#{tag}/text()")
      Statement.create!(webpage: page, source: source, cache: "2027-01-01", status: "ok", selected_individual: true)
      Statement.create!(webpage: archived, source: source, cache: "2026-10-01", status: "ok", selected_individual: true)
    end
    Statement.where(webpage: [page, archived]).update_all(status: "ok")
    assert @website.webpages.publishable.where(id: archived.id).exists?
    html = "<title>Event</title><address>Hall</address><time>2027-01-01</time>"
    cache = Distillator::FetchCache.create!(uri_key: CGI.escape(page.url), normalized_url: page.url, html: html, body: html,
      http_response_code: 200, scrape_date: Time.current, successful_refresh: Time.current, headers: {},
      signals: { transport_success: true, content_success: true, fetch_backend: "native" })
    calls = []
    fetcher = Object.new
    fetcher.define_singleton_method(:fetch) do |**options|
      calls << options
      Distillator::FetchCacheStore::Result.new(cache: cache, cache_hit: false, body: html, signals: cache.signals, fetch_path: "native")
    end
    comparer = Object.new
    comparer.define_singleton_method(:call) { |**| { legacy_cache: { html: html }, legacy_lookup_status: "ok", summary: {}, missing: {} } }
    exporter = Object.new
    %i[call production_equivalent].each { |name| exporter.define_singleton_method(name) { |**| '<https://example.org/event> <http://schema.org/name> "Event" .' } }
    runner = Object.new
    runner.define_singleton_method(:call) do |**options|
      Distillator::TransitionCheckRunner.call(**options, fetch_cache_store: fetcher, cache_compare: comparer, export_service: exporter)
    end
    batch = Distillator::TransitionBatch.request!(website_ids: [@website.id], request_key: SecureRandom.uuid, check_profile: "light")
    item = batch.site_transitions.sole
    processor = Distillator::SiteTransitionProcessor.new(runner: runner)
    assert_no_difference "Statement.count" do
      processor.perform(item.id, phase: "queued")
      processor.perform(item.id, phase: "postcheck")
    end
    assert_equal "passed", item.reload.status, item.reason
    assert_equal ["internal", nil], calls.map { |call| call[:mode] }
    assert_equal [page.url, page.url], calls.pluck(:uri)
    assert calls.all? { |call| call[:force_scrape] }
    pre = item.pre_run.transition_evidences.find_by!(check_kind: "fetch_parity").details
    post = item.post_run.transition_evidences.find_by!(check_kind: "fetch_parity").details
    assert_equal true, post["active_path_verification"]
    assert_equal pre.fetch("event_sample"), post.fetch("event_sample")
    assert_match(/\A\d+\z/, pre.dig("event_sample", "seed"))
    assert_equal [{ "id" => page.id, "url" => page.url }], pre.dig("event_sample", "pages")
    summary = Distillator::WebsiteValidationHistory.for_websites([@website.reload]).fetch(@website.id)
    assert_equal [1, 0, 1, 1], [summary.light, summary.thorough, summary.covered, summary.eligible]
    assert_nil summary.milestone
    assert_equal "active", @website.reload.distillator_mode

    page.update_column(:language, "fr")
    updated_summary = Distillator::WebsiteValidationHistory.for_websites([@website]).fetch(@website.id)
    assert_equal [1, 0, 0, 1], [updated_summary.light, updated_summary.thorough, updated_summary.covered, updated_summary.eligible]
    assert updated_summary.changed
  end

  private

  def create_site(seed)
    website = Website.create!(name: seed, seedurl: seed, graph_name: "https://example.org/#{seed}", default_language: "en", distillator_mode: "legacy")
    page = website.webpages.create!(url: "https://example.org/#{seed}/event", rdf_uri: "rdf:#{seed}", rdfs_class: rdfs_classes(:one), language: "en")
    { four: "Current event", location: '[["Salle","uri:place"]]', six: [1.month.from_now.iso8601].to_json }.each do |property, value|
      source = website.sources.create!(property: properties(property), language: "en", selected: true, algorithm_value: "manual=#{value}")
      statement = page.statements.create!(source: source, status: "ok", cache: value, selected_individual: true)
      statement.update_column(:status, "ok")
    end
    website
  end

  def request(**options)
    batch = Distillator::TransitionBatch.request!(website_ids: [@website.id], request_key: SecureRandom.uuid, **options)
    [batch, batch.site_transitions.sole]
  end
end
