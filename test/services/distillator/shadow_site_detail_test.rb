require "test_helper"

class Distillator::ShadowSiteDetailTest < ActiveSupport::TestCase
  test "builds read only detail sections without fetching" do
    website = Website.create!(
      name: "Hector Charland",
      seedurl: "hector-charland-com",
      graph_name: "https://example.org/hector-charland",
      default_language: "en",
      distillator_mode: "shadow"
    )
    url = "https://example.org/hector-charland/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:hector", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: url
    )

    detail = Distillator::ShadowSiteDetail.call(website: website)

    assert_equal website, detail.summary.website
    assert_includes detail.rollout_notes.join(" "), "La Vitrine pipeline"
  end

  test "root cause prioritizes statement failures over secondary legacy lookup issues" do
    website = Website.create!(
      name: "Statement priority",
      seedurl: "statement-priority",
      graph_name: "https://example.org/statement-priority",
      default_language: "en",
      distillator_mode: "shadow"
    )
    url = "https://example.org/statement-priority/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:statement-priority", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: url
    )
    website.transition_evidences.create!(
      url: url,
      check_kind: "fetch_parity",
      status: "checked",
      checked_at: 1.hour.ago,
      details: {
        reason: "legacy_lookup_missing_config",
        representative_webpages: [url],
        representative_webpage_count: 1,
        representative_url_results: [
          { url: url, fetch_status: "passed", fetch_reason: "ok", legacy_lookup_status: "missing_config", comparison_status: "review" }
        ]
      }
    )
    website.transition_evidences.create!(
      url: url,
      check_kind: "statement_delta",
      status: "failed",
      statement_count_delta_acceptable: false,
      checked_at: 1.hour.ago,
      details: {
        reason: "statement_refresh_failed",
        representative_webpages: [url],
        representative_webpage_count: 1,
        statements_failed_count: 1,
        failing_statements: [{ id: 42, source: "json_url / en", webpage_url: url }],
        refresh_errors: ["invalid url in json_url"]
      }
    )

    publish_transition_fixture(website)
    detail = Distillator::ShadowSiteDetail.call(website: website)

    assert_equal "statements", detail.root_cause[:failed_layer]
    assert_equal "Legacy statement check failed before critical/optional classification was available.", detail.root_cause[:concrete_reason]
    assert_equal true, detail.checked_scope[:legacy_statement_failure]
    assert_equal 1, detail.checked_scope[:statements_failed_count]
    assert_nil detail.checked_scope[:critical_statements_failed_count]
    assert_nil detail.checked_scope[:optional_statements_failed_count]
    assert_equal "unknown", detail.statement_failure_groups.first[:severity]
    assert_equal "Invalid URL from json_url", detail.statement_failure_groups.first[:reason]
    assert_equal "json_url / en", detail.statement_failure_groups.first[:source]
  end

  test "detail remains pending until the full run completes" do
    website = websites(:one)
    previous = publish_transition_fixture(website, at: 1.hour.ago)
    run = Distillator::TransitionRun.request!(website: website).run
    pending = Distillator::ShadowSiteDetail.call(website: website)
    assert pending.pending_transition_batch_check
    assert_equal previous.completed_at.to_i, pending.latest_transition_evidence_checked_at.to_i
    run.execute do
      Distillator::TransitionEvidence::REPORT_CHECK_KINDS.each do |kind|
        run.transition_evidences.create!(website: website, url: "https://example.org/event", check_kind: kind,
          status: "pending", checked_at: Time.current)
      end
      assert website.pending_transition_batch_check?
    end
    fresh = Distillator::ShadowSiteDetail.call(website: website.reload)
    assert_not fresh.pending_transition_batch_check
    assert_equal run.completed_at.to_i, fresh.latest_transition_evidence_checked_at.to_i
  end

  test "statement blocker counts distinct failed URLs rather than sampled pages or fields" do
    website = websites(:one)
    urls = 9.times.map { |index| "https://example.org/event/#{index}" }
    website.transition_evidences.create!(check_kind: "statement_delta", url: urls.first,
      status: "failed", statement_count_delta_acceptable: false, checked_at: Time.current,
      details: {
        reason: "strict_statement_parity_failed", comparison_basis: "paired_dsl",
        representative_webpages: urls, representative_webpage_count: 9,
        representative_url_statement_results: urls.each_with_index.map { |url, index|
          { url: url, status: index == 1 ? "failed" : (index == 2 ? "warning" : "passed") }
        },
        critical_failing_statements: ["Title", "Performed by"].map { |source|
          { source: source, webpage_url: urls.second }
        }
      })
    publish_transition_fixture(website)

    detail = Distillator::ShadowSiteDetail.call(website: website)
    assert_equal "statements", detail.root_cause[:failed_layer]
    assert_equal 1, detail.root_cause[:affected_url_count]
    assert_equal 9, detail.checked_scope[:representative_webpage_count]
    assert_equal 2, detail.statement_failure_groups.length
  end

  test "unlocated legacy statement failures do not claim the whole sample failed" do
    website = websites(:one)
    website.transition_evidences.create!(check_kind: "statement_delta", url: "https://example.org/first",
      status: "failed", statement_count_delta_acceptable: false, checked_at: Time.current,
      details: { reason: "statement_refresh_failed", representative_webpage_count: 9,
        statements_failed_count: 2, failing_statements: [{ source: "Title" }, { source: "Performed by" }] })
    publish_transition_fixture(website)

    detail = Distillator::ShadowSiteDetail.call(website: website)
    assert_equal "statements", detail.root_cause[:failed_layer]
    assert_nil detail.root_cause[:affected_url_count]
  end

  test "export blocker counts only URLs with unsuccessful export results" do
    website = websites(:one)
    urls = 9.times.map { |index| "https://example.org/event/#{index}" }
    website.transition_evidences.create!(check_kind: "export_diff", url: urls.first,
      status: "failed", export_diff_checked: true, export_diff_status: "failed", checked_at: Time.current,
      details: { reason: "export_diff_failed", representative_webpages: urls, representative_webpage_count: 9,
        representative_url_export_results: urls.each_with_index.map { |url, index|
          { url: url, status: index == 1 ? "failed" : "checked" }
        } })
    publish_transition_fixture(website, defaults: {
      "statement_delta" => { status: "checked", statement_count_delta_acceptable: true },
      "fetch_parity" => { status: "checked" }
    })

    detail = Distillator::ShadowSiteDetail.call(website: website)
    assert_equal "export", detail.root_cause[:failed_layer]
    assert_equal 1, detail.root_cause[:affected_url_count]
  end
end
