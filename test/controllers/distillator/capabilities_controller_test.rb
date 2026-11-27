require "test_helper"

class Distillator::CapabilitiesControllerTest < ActionDispatch::IntegrationTest
  test "capabilities page renders read only without fetch refresh export or rollout writes" do
    assert_read_only_capabilities_page

    assert_no_difference(["Distillator::FetchCache.count", "Distillator::RolloutEvent.count"]) do
      get distillator_capabilities_path
    end

    assert_response :success
    assert_match "Condenser / Distillator System Map", @response.body
    assert_match "This page is read-only", @response.body
    assert_match "Activation readiness ladder", @response.body
  end

  test "capabilities page shows grouped feature matrix and key features" do
    get distillator_capabilities_path

    assert_response :success
    assert_match "Fetch &amp; Cache", @response.body
    assert_match "Statement Extraction", @response.body
    assert_match "Sources / DSL", @response.body
    assert_match "JSON-LD Export", @response.body
    assert_match "Transition / Rollout", @response.body
    assert_match "Diagnostics / Reports", @response.body
    assert_match "Operations / Safety", @response.body
    assert_match "Legacy Wringer Compatibility", @response.body
    assert_match "Cache compare", @response.body
    assert_match "Extracted statement parity", @response.body
    assert_match "Export graph diff", @response.body
    assert_match "Transition report", @response.body
    assert_match "Rollback path", @response.body
    assert_match "Legacy Wringer compatibility endpoint", @response.body
    assert_match "Implemented", @response.body
    assert_match "Legacy-backed", @response.body
    assert_match "Transition-only", @response.body
    assert_match "Production-critical", @response.body
    assert_match "Read-only", @response.body
    assert_match "Writes data", @response.body
    assert_match "Needs review", @response.body
    assert_match "Deprecated", @response.body
  end

  private

  def assert_read_only_capabilities_page
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::CacheCompare.expects(:call).never
    Distillator::CacheRefreshPreview.expects(:call).never
    Distillator::FetchService.expects(:call).never
    Distillator::RefreshRunner.expects(:call).never
    Distillator::TransitionCheck.expects(:call).never
    Distillator::TransitionCheckRunner.expects(:call).never
    Distillator::RolloutTransition.expects(:call).never
    ExportArtsdataService.expects(:call).never
    ExportArtsdataService.expects(:production_equivalent).never
    Statements::ExtractedParityComparisonService.expects(:call).never
  end
end
