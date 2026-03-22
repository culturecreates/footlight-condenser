require 'test_helper'

class EventsControllerTest < ActionDispatch::IntegrationTest


  test "should get index for upcoming" do
    get website_events_path(seedurl: "one", format: :json)
    assert_response :success
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
    Dsl::DslAlgorithmRunner.expects(:new).never

    get event_pipeline_health_path(id: "uri1", format: :json)
    assert_response :success
  end

end
