require "test_helper"

class Distillator::SiteTransitionProcessorTest < ActiveSupport::TestCase
  class Runner
    attr_accessor :pre_failure, :post_failure, :callback
    attr_reader :calls
    def initialize
      @calls = []
    end
    def call(website:, transition_run:, verify_active_path:, require_native_path:)
      @calls << { website_id: website.id, active_path: verify_active_path, mode: website.distillator_mode, native_required: require_native_path }
      callback&.call(website, verify_active_path)
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

  test "already Active sites only verify their active path and recover on failure" do
    @website.update_column(:distillator_mode, "active")
    _, item = request
    @runner.post_failure = true
    @processor.perform(item.id, phase: "queued")
    assert_nil item.reload.pre_run
    assert_equal [true], @runner.calls.map { |call| call[:active_path] }
    assert_equal "shadow", @website.reload.distillator_mode
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
    { "Title" => "title", "Location" => "address", "Dates" => "time" }.each do |label, tag|
      property = Property.create!(label: label, uri: "https://example.org/property/#{label}", value_datatype: "MyString", rdfs_class: rdfs_classes(:one))
      source = @website.sources.create!(property: property, language: "en", selected: true, algorithm_value: "xpath=//#{tag}/text()")
      Statement.create!(webpage: page, source: source, cache: "2027-01-01", status: "ok")
    end
    Statement.where(webpage: page).update_all(status: "ok")
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
    _, item = request
    processor = Distillator::SiteTransitionProcessor.new(runner: runner)
    assert_no_difference "Statement.count" do
      processor.perform(item.id, phase: "queued")
      processor.perform(item.id, phase: "postcheck")
    end
    assert_equal "passed", item.reload.status, item.reason
    assert_equal ["internal", nil], calls.map { |call| call[:mode] }
    assert calls.all? { |call| call[:force_scrape] }
    assert_equal true, item.post_run.transition_evidences.find_by!(check_kind: "fetch_parity").details["active_path_verification"]
    assert_equal "active", @website.reload.distillator_mode
  end

  private

  def create_site(seed)
    website = Website.create!(name: seed, seedurl: seed, graph_name: "https://example.org/#{seed}", default_language: "en", distillator_mode: "legacy")
    website.webpages.create!(url: "https://example.org/#{seed}/event", rdf_uri: "rdf:#{seed}", rdfs_class: rdfs_classes(:one), language: "en")
    website
  end

  def request
    batch = Distillator::TransitionBatch.request!(website_ids: [@website.id], request_key: SecureRandom.uuid)
    [batch, batch.site_transitions.sole]
  end
end
