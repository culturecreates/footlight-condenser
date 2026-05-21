require "test_helper"

class Distillator::TransitionChecksControllerTest < ActionDispatch::IntegrationTest
  test "transition check runs for one website only and does not change rollout mode" do
    target = Website.create!(
      name: "Transition target",
      seedurl: "transition-target",
      graph_name: "https://example.org/transition-target",
      default_language: "en",
      distillator_mode: "shadow"
    )
    other = Website.create!(
      name: "Transition other",
      seedurl: "transition-other",
      graph_name: "https://example.org/transition-other",
      default_language: "en",
      distillator_mode: "legacy"
    )

    Distillator::TransitionCheckRunner.expects(:call).with(website: target).once.returns(
      Distillator::TransitionCheckRunner::Result.new(
        website: target,
        records: {
          fetch_parity: OpenStruct.new(status: "checked"),
          statement_delta: OpenStruct.new(status: "checked"),
          export_diff: OpenStruct.new(status: "pending")
        }
      )
    )

    post distillator_transition_checks_path, params: { website_id: target.id }

    assert_redirected_to distillator_shadow_report_site_path(target)
    follow_redirect!
    assert_includes @response.body, "Transition check incomplete: fetch checked, statements checked, export missing"
    assert_equal "shadow", target.reload.distillator_mode
    assert_equal "legacy", other.reload.distillator_mode
    assert_equal 0, target.transition_evidences.count
    assert_equal 0, other.transition_evidences.count
  end

  test "transition check redirects back to report detail when return_to is provided" do
    target = Website.create!(
      name: "Transition target",
      seedurl: "transition-target-return",
      graph_name: "https://example.org/transition-target-return",
      default_language: "en",
      distillator_mode: "shadow"
    )

    Distillator::TransitionCheckRunner.expects(:call).with(website: target).once.returns(
      Distillator::TransitionCheckRunner::Result.new(
        website: target,
        records: {
          fetch_parity: OpenStruct.new(status: "checked"),
          statement_delta: OpenStruct.new(status: "checked"),
          export_diff: OpenStruct.new(status: "checked")
        }
      )
    )

    post distillator_transition_checks_path, params: { website_id: target.id, return_to: distillator_shadow_report_site_path(target) }

    assert_redirected_to distillator_shadow_report_site_path(target)
  end

  test "transition check allows deliberate relative webpages return_to" do
    target = Website.create!(
      name: "Transition target",
      seedurl: "transition-target-webpages",
      graph_name: "https://example.org/transition-target-webpages",
      default_language: "en",
      distillator_mode: "shadow"
    )

    Distillator::TransitionCheckRunner.expects(:call).with(website: target).once.returns(
      Distillator::TransitionCheckRunner::Result.new(
        website: target,
        records: {
          fetch_parity: OpenStruct.new(status: "checked"),
          statement_delta: OpenStruct.new(status: "checked"),
          export_diff: OpenStruct.new(status: "checked")
        }
      )
    )

    return_to = "/webpages?seedurl=#{target.seedurl}"
    post distillator_transition_checks_path, params: { website_id: target.id, return_to: return_to }

    assert_redirected_to return_to
  end

  test "transition check rejects unsafe external return_to values" do
    target = Website.create!(
      name: "Transition target",
      seedurl: "transition-target-unsafe",
      graph_name: "https://example.org/transition-target-unsafe",
      default_language: "en",
      distillator_mode: "shadow"
    )

    Distillator::TransitionCheckRunner.expects(:call).with(website: target).once.returns(
      Distillator::TransitionCheckRunner::Result.new(
        website: target,
        records: {
          fetch_parity: OpenStruct.new(status: "checked"),
          statement_delta: OpenStruct.new(status: "checked"),
          export_diff: OpenStruct.new(status: "checked")
        }
      )
    )

    post distillator_transition_checks_path, params: { website_id: target.id, return_to: "https://evil.example/steal" }

    assert_redirected_to distillator_shadow_report_site_path(target)
  end

  test "transition check creates statement and export evidence records" do
    target = Website.create!(
      name: "Transition target live",
      seedurl: "transition-target-live",
      graph_name: "https://example.org/transition-target-live",
      default_language: "en",
      distillator_mode: "shadow"
    )
    url = "https://transition-target-live.example/event"
    target.webpages.create!(url: url, language: "en", rdf_uri: "rdf:transition-target-live", rdfs_class: rdfs_classes(:one))
    source = Source.create!(
      algorithm_value: "manual=Transition target live",
      selected: true,
      selected_by: "test",
      language: "en",
      render_js: false,
      property: properties(:four),
      website: target
    )
    Statement.create!(
      cache: "Transition target live",
      status: "ok",
      status_origin: "transition_checks_controller_test",
      cache_refreshed: 1.hour.ago,
      cache_changed: 1.hour.ago,
      source: source,
      webpage: target.webpages.first,
      selected_individual: true
    )
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "statement_count_delta_acceptable" => true,
        "export_diff_checked" => true
      },
      final_url: url,
      health_status: "healthy"
    )
    Distillator::RefreshRunner.expects(:call).once.returns([])
    export_json = '[{"@id":"event:1","name":"Transition target live"}]'
    ExportArtsdataService.expects(:call).with(seedurl: target.seedurl).once.returns(export_json)
    ExportArtsdataService.expects(:production_equivalent).with(seedurl: target.seedurl).once.returns(export_json)

    post distillator_transition_checks_path, params: { website_id: target.id }

    assert_redirected_to distillator_shadow_report_site_path(target)
    assert_equal "shadow", target.reload.distillator_mode
    assert_equal %w[export_diff fetch_parity statement_delta], target.transition_evidences.order(:check_kind).pluck(:check_kind)
    assert_equal "checked", target.latest_transition_evidence("statement_delta").status
    assert_equal 0, target.latest_transition_evidence("statement_delta").statement_delta
    assert_equal "checked", target.latest_transition_evidence("export_diff").status

    follow_redirect!
    assert_includes @response.body, "Transition evidence"
    assert_includes @response.body, "Statements check passed."
  end

  test "report detail displays actionable reason fields for latest evidence" do
    target = Website.create!(
      name: "Transition target detail",
      seedurl: "transition-target-detail",
      graph_name: "https://example.org/transition-target-detail",
      default_language: "en",
      distillator_mode: "shadow"
    )
    url = "https://transition-target-detail.example/event"
    target.webpages.create!(url: url, language: "en", rdf_uri: "rdf:transition-target-detail", rdfs_class: rdfs_classes(:one))
    Distillator::TransitionEvidenceRecorder.call(
      website: target,
      url: url,
      check_kind: :statement_delta,
      status: :failed,
      statement_delta: 2,
      statement_count_delta_acceptable: false,
      details: { reason: "statement_refresh_failed" }
    )
    Distillator::TransitionEvidenceRecorder.call(
      website: target,
      url: url,
      check_kind: :export_diff,
      status: :failed,
      export_diff_status: "failed",
      rdf_added_count: 1,
      rdf_removed_count: 3,
      details: { reason: "export_generation_failed" }
    )

    get distillator_shadow_report_site_path(target)

    assert_response :success
    assert_includes @response.body, "Statement refresh failed for 2 statements."
    assert_includes @response.body, "Export could not be generated."
    assert_includes @response.body, "RDF added: 1"
    assert_includes @response.body, "RDF removed: 3"
  end
end
