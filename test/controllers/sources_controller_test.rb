require 'test_helper'

class SourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @source = sources(:one)
  end

  test "should get index" do
    Distillator::FetchService.expects(:fetch).never

    get sources_url

    assert_response :success
    assert_match "Quick filters", @response.body
    assert_match "Advanced filters", @response.body
    assert_match "name=\"term\"", @response.body
    assert_match "name=\"property_id\"", @response.body
    assert_match "name=\"language\"", @response.body
    assert_match "name=\"selected\"", @response.body
    assert_match "name=\"auto_review\"", @response.body
    assert_match "name=\"render_js\"", @response.body

    assert_operator @response.body.index("Quick filters"), :<, @response.body.index("Advanced filters")
    assert_operator @response.body.index("Advanced filters"), :<, @response.body.index("sort=property_id")
    assert_select "th a", text: /ID/
    assert_select "th a", text: /Property/
    assert_select "th a", text: /Label/
    assert_select "th a", text: /Algorithm value/
    assert_select "th a", text: /Selected/
    assert_select "th a", text: /Render JS/
    assert_select "th a", text: /Auto review/
    assert_select "th a", text: /Last test/
    assert_select "th", text: "Actions"
  end

  test "sources index renders harmonized table shell and filters" do
    Distillator::FetchService.expects(:fetch).never

    get sources_url

    assert_response :success
    assert_select ".harmonized-table-shell", 1
    assert_select ".harmonized-table-filters", 1
    assert_select 'form[action="/sources"][method="get"]', 1
    assert_select 'input[type="submit"][value="Apply filters"]', 1
    assert_select 'a', text: "Reset filters"
  end

  test "sources index renders sortable headers" do
    Distillator::FetchService.expects(:fetch).never

    get sources_url

    assert_response :success
    assert_select 'th a[href*="sort=id"]', text: /ID/
    assert_select 'th a[href*="sort=property_id"]', text: /Property/
    assert_select 'th a[href*="sort=algorithm_value"]', text: /Algorithm value/
    assert_select 'th a[href*="sort=render_js"]', text: /Render JS/
    assert_select 'th a[href*="sort=updated_at"]', text: /Last test/
  end

  test "sources index preserves active filters in sort links" do
    Distillator::FetchService.expects(:fetch).never

    get sources_url, params: { term: "query", selected: "true", language: "en", per_page: "10" }

    assert_response :success
    assert_sort_link_preserves_filters(
      label: "Algorithm value",
      sort_key: "algorithm_value",
      params: {
        term: "query",
        selected: "true",
        language: "en",
        per_page: "10"
      }
    )
  end

  test "sources index filters through controller params using sources index query" do
    Distillator::FetchService.expects(:fetch).never
    matching = Source.create!(
      algorithm_value: "controller query match",
      selected: true,
      selected_by: "Operator",
      language: "fr",
      render_js: true,
      property: properties(:one),
      website: websites(:one),
      auto_review: true
    )
    non_matching = Source.create!(
      algorithm_value: "controller query miss",
      selected: false,
      selected_by: "Operator",
      language: "en",
      render_js: false,
      property: properties(:two),
      website: websites(:two),
      auto_review: false
    )

    get sources_url, params: { term: "controller query", language: "fr", render_js: "true" }

    assert_response :success
    assert_includes @response.body, matching.algorithm_value
    assert_not_includes @response.body, non_matching.algorithm_value
  end

  test "sources index renders property label and visible dsl in main table" do
    Distillator::FetchService.expects(:fetch).never
    website = websites(:one)
    property = properties(:one)

    xpath_source = Source.create!(
      algorithm_value: "xpath=//div[@class='event-title']",
      label: "XPath title",
      selected: true,
      selected_by: "Operator",
      language: "en",
      render_js: false,
      property: property,
      website: website,
      auto_review: false
    )
    ruby_source = Source.create!(
      algorithm_value: "ruby=nodes.map(&:text)",
      label: "Ruby title",
      selected: false,
      selected_by: "Operator",
      language: "fr",
      render_js: false,
      property: property,
      website: website,
      auto_review: false
    )
    json_source = Source.create!(
      algorithm_value: "json_url=https://example.test/events.json",
      label: "JSON title",
      selected: false,
      selected_by: "Operator",
      language: "",
      render_js: true,
      property: property,
      website: website,
      auto_review: true
    )
    manual_source = Source.create!(
      algorithm_value: "manual=Festival Example",
      label: "Manual title",
      selected: false,
      selected_by: "Operator",
      language: "",
      render_js: false,
      property: property,
      website: website,
      auto_review: false
    )

    get sources_url, params: { seedurl: website.seedurl }

    assert_response :success
    assert_select "th a", text: /Property/
    assert_select "th a", text: /Label/
    assert_select "td.source-algorithm-cell pre", text: /xpath=/
    assert_select "td.source-algorithm-cell pre", text: /ruby=/
    assert_select "td.source-algorithm-cell pre", text: /json_url=/
    assert_select "td.source-algorithm-cell pre", text: /manual=/
    assert_includes @response.body, property.label
    assert_includes @response.body, xpath_source.label
    assert_includes @response.body, ruby_source.label
    assert_includes @response.body, json_source.label
    assert_includes @response.body, manual_source.label
  end

  test "sources index falls back safely for invalid sort and direction" do
    Distillator::FetchService.expects(:fetch).never

    get sources_url, params: { sort: "bogus", direction: "sideways" }

    assert_response :redirect
    assert_redirected_to "/sources"
  end

  test "sources index renders empty state" do
    Distillator::FetchService.expects(:fetch).never

    get sources_url, params: { term: "no-such-source-filter" }

    follow_redirect! if response.redirect?
    assert_response :success
    assert_select ".harmonized-table-empty-state", 1
  end

  test "sources index does not fetch" do
    assert_read_only_page_does_not_fetch

    get sources_url

    assert_response :success
  end

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
    assert_includes @response.body, "Active"
    assert_includes @response.body, "Condenser serves production while Wringer stays available for diagnostics."
    assert_includes @response.body, "Production: Condenser"
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
    assert_includes @response.body, "Shadow"
    assert_includes @response.body, "Wringer serves production while Condenser is checked in the background."
    assert_includes @response.body, "Production: Wringer"
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
    assert_select ".source-form-cards .source-algorithm-card", 1
    assert_select ".source-form-cards .source-diagnostics-card", 1
    assert_match "Identity", @response.body
    assert_match "Activation", @response.body
    assert_match "Fetch strategy", @response.body
    assert_match "Extraction algorithm", @response.body
    assert_match "Diagnostics", @response.body
    assert_match "Website default", @response.body
    assert_match "Raw extraction DSL", @response.body
    assert_match "Use pipeline steps such as", @response.body
    assert_operator @response.body.index("source-algorithm-card"), :<, @response.body.index("source-diagnostics-card")
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
