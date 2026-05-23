require "test_helper"
require "rake"

class DistillatorTransitionTaskTest < ActiveSupport::TestCase
  setup do
    Distillator::TransitionEvidence.delete_all
    Distillator::FetchCache.delete_all
    Website.where(seedurl: "task-runner-site").find_each(&:destroy)

    Rails.application.load_tasks unless Rake::Task.task_defined?("distillator:transition:check")
    @check_task = Rake::Task["distillator:transition:check"]
    @preflight_task = Rake::Task["distillator:transition:preflight"]
    @check_task.reenable
    @preflight_task.reenable
  end

  test "task prints operator facing check summary and detail path" do
    website = Website.create!(
      name: "Task runner site",
      seedurl: "task-runner-site",
      graph_name: "https://example.org/task-runner-site",
      default_language: "en",
      distillator_mode: "shadow"
    )
    url = "https://task-runner-site.example/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:task-runner-site", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: url,
      health_status: "healthy"
    )
    Distillator::TransitionCheckRunner.expects(:call).with(website: website.id).returns(
      OpenStruct.new(website: website)
    )
    Distillator::TransitionCheck.expects(:call).with(website: website).returns(
      OpenStruct.new(fetch: :passed, statements: :missing, export: :missing, status: :review)
    )

    stdout, = capture_io do
      @check_task.invoke(website.id)
    end

    assert_includes stdout, "Fetch: Passed"
    assert_includes stdout, "Statements: Missing"
    assert_includes stdout, "Export: Missing"
    assert_includes stdout, "Overall: Needs review"
    assert_includes stdout, "Open: /distillator/shadow_report/#{website.id}"
  end

  test "preflight task prints second production readiness checks without fetching" do
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never
    HTTParty.expects(:get).never
    ApplicationController.helpers.stubs(:get_wringer_url_per_environment).returns("http://wringer.example")

    stdout, = capture_io do
      @preflight_task.invoke
    end

    assert_includes stdout, "Database: OK"
    assert_includes stdout, "Queue adapter:"
    assert_includes stdout, "Rollout modes: legacy/shadow/active available"
    assert_includes stdout, "Default mode: legacy"
    assert_includes stdout, "Cache table: OK"
    assert_includes stdout, "Transition Report route: OK"
    assert_includes stdout, "Compare route: OK"
    assert_includes stdout, "Wringer inspection base: configured"
  end

  test "preflight task prints staging rollout mode failure when staging has invalid websites" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    ApplicationController.helpers.stubs(:get_wringer_url_per_environment).returns("http://wringer.example")
    Website.create!(
      name: "Task preflight legacy",
      seedurl: "task-preflight-legacy",
      graph_name: "https://example.org/task-preflight-legacy",
      default_language: "en",
      distillator_mode: "legacy"
    )

    error = nil
    stdout, = capture_io do
      error = assert_raises(Distillator::ProductionPreflight::Failure) do
        @preflight_task.invoke
      end
    end

    assert_includes stdout, "Staging rollout modes: Staging requires every website to be Shadow or Active."
    assert_includes stdout, "Preflight: FAILED"
    assert_equal "Second-production preflight failed", error.message
  ensure
    ENV["DISTILLATOR_RUNTIME"] = nil
  end

  test "preflight task raises with clear failure output" do
    failing_result = Distillator::ProductionPreflight::Result.new(
      entries: [
        Distillator::ProductionPreflight::Entry.new(label: "Database", value: "FAILED (boom)", ok: false)
      ]
    )
    Distillator::ProductionPreflight.stubs(:call).returns(failing_result)

    error = nil
    stdout, = capture_io do
      error = assert_raises(Distillator::ProductionPreflight::Failure) do
        @preflight_task.invoke
      end
    end

    assert_includes stdout, "Database: FAILED (boom)"
    assert_includes stdout, "Preflight: FAILED"
    assert_equal "Second-production preflight failed", error.message
  end
end
