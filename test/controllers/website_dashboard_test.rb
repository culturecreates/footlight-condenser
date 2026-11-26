require "test_helper"

class WebsiteDashboardTest < ActionDispatch::IntegrationTest
  test "a wildcard Accept header renders the dashboard as HTML" do
    get websites_path, params: { dashboard: "action" }, headers: { "Accept" => "*/*" }
    assert_response :success
    assert_equal "text/html", response.media_type
    assert_select "nav[aria-label='Dashboard perspective'] [aria-current=page]", text: "Action"
  end

  test "perspective, Preferred, cohort and sort are independent and the default is stored in a browser cookie" do
    site = websites(:one)
    site.update_columns(preferred: true, seedurl: "co-motion-ca", name: "Co-motion Laval")
    options = { view: "preferred", cohort: "client_sites", q: "Co-motion", sort: "name", direction: "desc" }
    get websites_path, params: options
    assert_response :success
    assert_select "nav[aria-label='Dashboard perspective'] [aria-current=page]", text: "Information"
    assert_select "nav[aria-label='Dashboard perspective'] a[href=?]", websites_path(options.merge(dashboard: "action")), text: "Action"
    assert_select "nav[aria-label='Website lists'] [aria-current=page]", text: /Preferred/
    assert_select "th", text: "Data health"
    assert_select "a[href=?]", websites_path(options.merge(metrics: "full")), text: "Show all metrics"
    assert_select "th", text: "Inventory freshness", count: 0

    patch default_dashboard_websites_path, params: options.merge(dashboard: "action")
    assert_redirected_to websites_path(options.merge(dashboard: "action"))
    get websites_path, params: options
    assert_select "nav[aria-label='Dashboard perspective'] [aria-current=page]", text: "Action"
    assert_select "a[href*='dashboard=action'][href*='sort=name'][href*='view=preferred']", text: /Website/
    assert_select "tr.website-index-row", count: 1
    assert_select "tr[data-website-id='#{site.id}']"

    get websites_path, params: options.merge(dashboard: "information")
    assert_select "th", text: "Data health"
    get websites_path(format: :json), params: options.merge(dashboard: "action", action_filter: "progress")
    assert_equal [site.id], response.parsed_body.pluck("id")
  end

  test "a missing required Location links to the relevant Event statements and reads have no operational side effects" do
    site = websites(:one)
    site.update_column(:distillator_mode, "active")
    webpage = site.webpages.create!(url: "https://example.org/a-dashboard-event", rdf_uri: "urn:dashboard:no-location",
      language: "en", rdfs_class: rdfs_classes(:one))
    %i[four six].each do |property|
      source = site.sources.create!(property: properties(property), language: "en", selected: true, algorithm_value: "manual=Value")
      webpage.statements.create!(source: source, status: "ok", cache: "2027-01-04", selected_individual: true)
        .update_column(:status, "ok")
    end

    Distillator::FetchService.expects(:fetch_result).never
    Distillator::RefreshRunner.expects(:call).never
    AddWebpagesJob.expects(:perform_now).never
    assert_no_changes -> { site.reload.distillator_mode } do
      assert_no_difference ["Distillator::TransitionRun.count", "Distillator::TransitionBatch.count", "Statement.count"] do
        get websites_path, params: { dashboard: "action", action_filter: "attention", q: site.name }
      end
    end

    assert_response :success
    row = "tr[data-website-id='#{site.id}']"
    assert_select "#{row} [data-action-code=missing_event_fields]", text: /Location unavailable/
    assert_select "#{row} a[href=?]", statements_path(seedurl: site.seedurl, rdf_uri: webpage.rdf_uri), text: "Review event statements"
    assert_select "#{row} button[data-website-details][aria-controls='website-details-#{site.id}'][aria-expanded=false]"
    assert_select "a[href=?]", webpages_path(seedurl: site.seedurl, scope: "all")
  end

  test "reviewing a recommendation only prepares the existing Thorough form for one website" do
    site = websites(:one)
    site.update_column(:distillator_mode, "active")
    assert_no_difference "Distillator::TransitionBatch.count" do
      get websites_path, params: { view: "all", dashboard: "action", transition_website_id: site.id }
    end
    assert_response :success
    assert_select "input[data-transition-site]", count: 1
    assert_select "input[data-transition-site][value='#{site.id}'][checked][form=website-transition-batch]"
    assert_select "form#website-transition-batch[action=?]", distillator_transition_batches_path do
      assert_select "input[type=hidden][name=check_profile][value=thorough]"
      assert_select "select[name=check_profile]", count: 0
      assert_select "p", text: /To run a Light check, go back to the website list/
      assert_select "button[data-transition-audit]", text: "Audit selected Active sites (Thorough)"
    end
    assert_match(/may move Active sites to Shadow/, response.body)

    get websites_path, params: { view: "all", dashboard: "action" }
    assert_select "form#website-transition-batch select[name=check_profile] option[value=light]"
  end

  test "active workflow progress is available even when other findings exist" do
    site = websites(:one)
    site.update_column(:distillator_mode, "active")
    old_check = Distillator::TransitionRun.request!(website: site).run
    old_check.update!(status: "failed", completed_at: Time.current, error_message: "The previous comparison was interrupted.")
    group = Distillator::TransitionBatch.request!(website_ids: [site.id], request_key: SecureRandom.uuid, workflow_action: "audit")
    workflow = group.site_transitions.sole

    %w[all progress attention].each do |filter|
      get websites_path, params: { dashboard: "action", action_filter: filter, q: site.name, view: "all" }
      assert_response :success
      assert_select "tr.website-index-row", count: 1
      assert_select "[data-action-code=audit_in_progress]", text: /Active audit queued/
      assert_select "a[href=?]", distillator_site_transition_path(workflow), text: "Open workflow report"
      assert_select "#website-details-#{site.id} [aria-label='Action evidence'] li", text: /previous comparison was interrupted/
    end
    assert_equal "active", site.reload.distillator_mode
  end

  test "staging-invalid sites outside event transitions appear in the queue without selection controls" do
    resource_list = websites(:one)
    resource_list.update_columns(name: "Festival Resource List", seedurl: "festival-rlist", distillator_mode: "legacy")
    Distillator::TransitionRuntime.stubs(:staging?).returns(true)

    get websites_path, params: { dashboard: "action", action_filter: "attention", distillator_mode: "invalid_on_staging",
      view: "all", q: resource_list.name }

    assert_response :success
    assert_match(/websites are invalid on staging/, response.body)
    assert_select "tr[data-website-id='#{resource_list.id}']" do
      assert_select "[data-action-code=staging_mode]", text: /This site is in Legacy mode/
      assert_select "a[href=?]", website_path(resource_list), text: "Review website"
      assert_select "input[data-transition-site]", count: 0
    end
  end
end
