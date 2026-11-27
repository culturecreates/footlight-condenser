require 'test_helper'

class EventsControllerTest < ActionDispatch::IntegrationTest
  test "events index does not fetch" do
    assert_read_only_page_does_not_fetch

    get website_events_path(seedurl: "one")

    assert_response :success
  end

  test "should get index for upcoming" do
    get website_events_path(seedurl: "one", format: :json)
    assert_response :success
  end

  test "events json index preserves event row contract" do
    get website_events_path(seedurl: "one", format: :json)

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal "one", payload["seedurl"]
    assert_includes payload.keys, "total_events"
    assert_includes payload.keys, "events"
    assert payload["events"].is_a?(Array)
  end

  test "events index renders harmonized table shell filters and sortable headers" do
    get website_events_path(seedurl: "one")

    assert_response :success
    assert_select ".harmonized-table-shell", 1
    assert_select ".harmonized-table-filters", 1
    assert_select 'form[action="/websites/one/events"][method="get"]', 1
    assert_select 'input[type="submit"][value="Apply filters"]', 1
    assert_select 'a', text: "Reset filters"
    assert_select 'th a[href*="sort=title"]'
    assert_select 'th a[href*="sort=archive_date"]'
  end

  test "events json returns the complete collection rather than its first page" do
    stub_event_collection(125)
    assert_read_only_page_does_not_fetch

    get website_events_path(seedurl: "one", format: :json)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 125, payload["total_events"]
    assert_equal 125, payload["events"].length
    assert_equal 125, payload["events"].map { |event| event["rdf_uri"] }.uniq.length
    assert payload["events"].all? { |event| event.dig("statements_status", "publishable") }
  end

  test "events json ignores HTML pagination parameters while preserving filters and sorting" do
    stub_event_collection(125)

    get website_events_path(seedurl: "one", format: :json), params: {
      page: 2, per_page: 100, term: "Event", sort: "title", direction: "desc",
      startDate: "2020-01-01", endDate: "2035-01-01"
    }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 125, payload["total_events"]
    assert_equal 125, payload["events"].length
    assert_equal "Event 125", payload["events"].first["title"]
    assert_equal "Event 001", payload["events"].last["title"]
  end

  test "events json reports zero when the complete filtered collection is empty" do
    stub_event_collection(125)

    get website_events_path(seedurl: "one", format: :json), params: { term: "no matching event" }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 0, payload["total_events"]
    assert_empty payload["events"]
  end

  test "events HTML retains its page size and full result total" do
    stub_event_collection(125)

    get website_events_path(seedurl: "one"), params: { page: "2" }

    assert_response :success
    assert_select "h1", text: "Events 125"
    assert_select "tbody tr", count: 25
  end

  test "events index preserves active filters in sort links" do
    get website_events_path(seedurl: "one"), params: { startDate: "2018-01-01", endDate: "2030-01-01", per_page: "10" }

    assert_response :success
    assert_sort_link_preserves_filters(
      label: "Title",
      sort_key: "title",
      params: {
        startDate: "2018-01-01",
        endDate: "2030-01-01",
        per_page: "10"
      }
    )
  end

  test "events index falls back safely for invalid sort and direction" do
    get website_events_path(seedurl: "one"), params: { sort: "bogus", direction: "sideways" }

    assert_response :redirect
    assert_redirected_to website_events_path(seedurl: "one")
  end

  test "events nested canonical redirect does not duplicate seedurl query param" do
    get website_events_path(seedurl: "one"), params: {
      sort: "bogus",
      direction: "sideways",
      seedurl: "one"
    }

    assert_response :redirect
    assert_redirected_to website_events_path(seedurl: "one")
    assert_not_includes response.location, "?seedurl=one"
  end

  test "events index renders empty state" do
    get website_events_path(seedurl: "one"), params: { startDate: "2100-01-01", endDate: "2100-12-31" }

    assert_response :success
    assert_select ".harmonized-table-empty-state", 1
  end

  test "pipeline health endpoint returns contract structure" do
    get event_pipeline_health_path(id: "uri1", format: :json)
    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal "uri1", payload["event_id"]

    pipeline = payload["pipeline"]
    assert pipeline.is_a?(Hash)
    assert_includes pipeline.keys, "status"
    assert_includes pipeline.keys, "category"
    assert_includes pipeline.keys, "message"
    assert_includes pipeline.keys, "suggested_action"
    assert_includes pipeline.keys, "metrics"
    assert_includes pipeline.keys, "details"
    assert pipeline["metrics"].is_a?(Hash)
    assert pipeline["details"].is_a?(Hash)
  end

  test "pipeline health diagnosis mapping matches evaluator output" do
    expected = Dsl::PipelineEvaluator.evaluate(event: "uri1")

    get event_pipeline_health_path(id: "uri1", format: :json)
    assert_response :success

    pipeline = JSON.parse(response.body).fetch("pipeline")
    assert_equal expected[:diagnosis][:status].to_s, pipeline["status"]
    assert_equal expected[:diagnosis][:category].to_s, pipeline["category"]
    assert_equal expected[:diagnosis][:suggested_action].to_s, pipeline["suggested_action"]
  end

  test "pipeline health handles missing pipeline data gracefully" do
    get event_pipeline_health_path(id: "missing-uri", format: :json)
    assert_response :success

    pipeline = JSON.parse(response.body).fetch("pipeline")
    assert pipeline["metrics"].is_a?(Hash)
    assert_equal 0, pipeline["metrics"]["steps_count"]
  end

  test "pipeline health endpoint does not execute dsl runner" do
    Dsl::Core::AlgorithmRunner.expects(:new).never

    get event_pipeline_health_path(id: "uri1", format: :json)
    assert_response :success
  end

  private

  def stub_event_collection(count)
    rows = (1..count).to_h do |id|
      number = format("%03d", id)
      ["event:#{number}", {
        "title" => { cache: "Event #{number}", status: "ok" },
        "dates" => { cache: "2030-01-01", status: "ok" },
        "location" => { cache: "Venue", status: "ok" },
        archive_date: { cache: Date.new(2030, 1, 2) }
      }]
    end
    Events::IndexQuery.any_instance.stubs(:website_statements_by_event).returns(rows)
  end

  def assert_read_only_page_does_not_fetch
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never
  end

end
