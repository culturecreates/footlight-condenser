require 'test_helper'

class SourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @source = sources(:one)
  end

  test "should get index" do
    Distillator::FetchService.expects(:fetch).never
    @source.website.update!(distillator_mode: "legacy")

    get sources_url

    assert_response :success
    assert_includes @response.body, "Legacy Wringer active"
    assert_match "Quick filters", @response.body
    assert_match "Advanced filters", @response.body
    assert_match "name=\"source_term\"", @response.body
    assert_match "name=\"source_property\"", @response.body
    assert_match "name=\"source_language\"", @response.body
    assert_match "name=\"source_selected_by\"", @response.body
    assert_match "name=\"source_status\"", @response.body
    assert_match "name=\"source_strategy\"", @response.body
    assert_match "name=\"source_pipeline\"", @response.body
    assert_match "name=\"source_needs_test\"", @response.body
    assert_no_match "<th>Algorithm value</th>", @response.body

    header_positions = [
      @response.body.index("<th>Status</th>"),
      @response.body.index("<th>Property / Language</th>"),
      @response.body.index("<th>Pipeline</th>"),
      @response.body.index("<th>Fetch strategy</th>"),
      @response.body.index("<th>Impact</th>"),
      @response.body.index("<th>Last test</th>"),
      @response.body.index("<th>Actions</th>")
    ]

    assert header_positions.all?
    assert_operator @response.body.index("Quick filters"), :<, @response.body.index("Advanced filters")
    assert_operator @response.body.index("Advanced filters"), :<, @response.body.index("<th>Status</th>")
    assert_equal header_positions.sort, header_positions
  end

  # test "should get new" do
  #   get new_source_url
  #   assert_response :success
  # end
  #
  # test "should get new of specific class rdfs_class :one" do
  #   get new_source_url(rdfs_class_id: :one)
  #   assert_response :success
  # end

  test "should create source" do
    assert_difference('Source.count') do
      post sources_url, params: { source: { algorithm_value: @source.algorithm_value,  property_id: @source.property_id, render_js: @source.render_js, selected: @source.selected, selected_by: @source.selected_by, website_id: @source.website_id } }
    end

    assert_redirected_to source_url(Source.last)
  end

  test "should show source" do
    assert_read_only_page_does_not_fetch
    @source.website.update!(distillator_mode: "active")

    get source_url(@source)

    assert_response :success
    assert_select 'details[data-operator-context-card]'
    assert_select 'details[data-context-domain="status"]'
    assert_select 'details[data-context-domain="actions"]'
    assert_select 'details[data-context-domain="details"]'
    assert_includes @response.body, "Condenser active"
    assert_includes @response.body, "Condenser serves fetch/cache results; legacy Wringer remains available for inspection."
    assert_includes @response.body, "Active: Condenser"
    assert_match "Status / rollout", @response.body
    assert_match "Extraction rule", @response.body
    assert_match "Pipeline", @response.body
    assert_match "Fetch strategy", @response.body
    assert_match "Impact", @response.body
    assert_match "Compatibility", @response.body
    assert_match "Raw diagnostics", @response.body
    assert_match "Primary", @response.body
    assert_match "Diagnostics", @response.body
    assert_match "Danger zone", @response.body
    assert_match "This source is the website default for this property/language.", @response.body
    assert_match "Raw extraction DSL", @response.body
  end

  test "show source explains activation impact for alternative source" do
    assert_read_only_page_does_not_fetch

    get source_url(sources(:two))

    assert_response :success
    assert_match "Activating this source will make it the website default for this property/language and replace the current default source for that scope.", @response.body
  end

  test "website view uses operator table without fetching" do
    Distillator::FetchService.expects(:fetch).never
    @source.website.update!(distillator_mode: "shadow")

    get website_sources_url(id: @source.website_id)

    assert_response :success
    assert_includes @response.body, "Shadow comparison"
    assert_includes @response.body, "Wringer serves production results; Condenser compares in the background."
    assert_includes @response.body, "Active: Wringer + Shadow comparison"
    assert_match "Quick filters", @response.body
    assert_match "Advanced filters", @response.body
    assert_match "More", @response.body
    assert_match "Primary", @response.body
    assert_match "Diagnostics", @response.body
    assert_match "Danger zone", @response.body
    assert_match "Open active cache", @response.body
    assert_match "Open Condenser cache", @response.body
    assert_match "Inspect legacy Wringer", @response.body
    assert_no_match "new cache", @response.body
  end

  test "should get edit" do
    Distillator::FetchService.expects(:fetch).never

    get edit_source_url(@source)

    assert_response :success
    assert_match "Identity", @response.body
    assert_match "Activation", @response.body
    assert_match "Fetch strategy", @response.body
    assert_match "Extraction algorithm", @response.body
    assert_match "Diagnostics", @response.body
    assert_match "Website default", @response.body
    assert_match "Raw extraction DSL", @response.body
    assert_match "Use pipeline steps such as", @response.body
  end

  test "index exposes new source entry points and edit form contains grouped operator sections" do
    Distillator::FetchService.expects(:fetch).never

    get sources_url

    assert_response :success
    assert_match "New Event Source", @response.body

    Distillator::FetchService.expects(:fetch).never
    get edit_source_url(@source)
    assert_response :success
    assert_match "Identity", @response.body
    assert_match "Activation", @response.body
    assert_match "Fetch strategy", @response.body
    assert_match "Extraction algorithm", @response.body
    assert_match "Diagnostics", @response.body
    assert_match "Raw extraction DSL", @response.body
  end

  test "should update source" do
    patch source_url(@source), params: { source: { algorithm_value: @source.algorithm_value, property_id: @source.property_id, render_js: @source.render_js, selected: @source.selected, selected_by: @source.selected_by, website_id: @source.website_id } }
    assert_redirected_to source_url(@source)
  end

  test "should destroy source" do
    assert_difference('Source.count', -1) do
      delete source_url(@source)
    end

    assert_redirected_to sources_url
  end

  private

  def assert_read_only_page_does_not_fetch
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never
  end
end
