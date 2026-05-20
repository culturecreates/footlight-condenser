require "test_helper"

class Distillator::RolloutTransitionTest < ActiveSupport::TestCase
  setup do
    @old_override_flag = ENV["DISTILLATOR_ALLOW_ACTIVE_OVERRIDE"]
    @old_heroku_app_name = ENV["HEROKU_APP_NAME"]
  end

  teardown do
    ENV["DISTILLATOR_ALLOW_ACTIVE_OVERRIDE"] = @old_override_flag
    ENV["HEROKU_APP_NAME"] = @old_heroku_app_name
  end

  test "blocks direct legacy to active by default" do
    website = build_website("legacy")

    result = Distillator::RolloutTransition.call(website: website, to_mode: "active", actor: "test")

    assert_equal false, result.success?
    assert_equal "legacy", website.reload.distillator_mode
    assert_includes result.errors, "Direct legacy to active promotion is blocked"
  end

  test "blocks shadow to active when status is review" do
    website = build_website("shadow")
    url = "https://example.org/review"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:review", rdfs_class: rdfs_classes(:one))
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

    result = Distillator::RolloutTransition.call(website: website, to_mode: "active", actor: "test")

    assert_equal false, result.success?
    assert_includes result.errors, "Cannot activate yet: statements check is missing."
  end

  test "allows shadow to active when status is ready" do
    website = build_website("shadow", seedurl: "hector-charland-com")
    url = "https://example.org/ready"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:ready", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true, "statement_count_delta_acceptable" => true, "export_diff_checked" => true },
      final_url: url
    )
    website.transition_evidences.create!(
      url: url,
      check_kind: "statement_delta",
      status: "checked",
      statement_count_delta_acceptable: true,
      checked_at: 1.hour.ago
    )
    website.transition_evidences.create!(
      url: url,
      check_kind: "export_diff",
      status: "checked",
      export_diff_checked: true,
      checked_at: 1.hour.ago
    )

    result = Distillator::RolloutTransition.call(website: website, to_mode: "active", actor: "test")

    assert_equal true, result.success?
    assert_equal "active", website.reload.distillator_mode
  end

  test "allows active rollback to legacy even when readiness would fail" do
    website = build_website("active", seedurl: "hector-charland-com")

    result = Distillator::RolloutTransition.call(website: website, to_mode: "legacy", actor: "test")

    assert_equal true, result.success?
    assert_equal "legacy", website.reload.distillator_mode
  end

  test "activate anyway succeeds when explicit override flag is enabled" do
    ENV["DISTILLATOR_ALLOW_ACTIVE_OVERRIDE"] = "true"
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))
    website = build_website("legacy", seedurl: "override-flag")

    result = Distillator::RolloutTransition.call(
      website: website,
      to_mode: "active",
      actor: "test",
      reason: "Manual check complete",
      override: true
    )

    assert_equal true, result.success?
    assert_equal "active", website.reload.distillator_mode
  ensure
    Rails.unstub(:env)
  end

  test "activate anyway succeeds on known staging heroku app" do
    ENV["HEROKU_APP_NAME"] = "footlight-condenser-staging"
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))
    website = build_website("shadow", seedurl: "override-staging")

    result = Distillator::RolloutTransition.call(
      website: website,
      to_mode: "active",
      actor: "test",
      reason: "Staging acceptance",
      override: true
    )

    assert_equal true, result.success?
    assert_equal "active", website.reload.distillator_mode
  ensure
    Rails.unstub(:env)
  end

  test "activate anyway fails outside allowed runtime when env flag is absent" do
    ENV["DISTILLATOR_ALLOW_ACTIVE_OVERRIDE"] = nil
    ENV["HEROKU_APP_NAME"] = nil
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))
    website = build_website("shadow", seedurl: "override-blocked")

    result = Distillator::RolloutTransition.call(
      website: website,
      to_mode: "active",
      actor: "test",
      reason: "Not allowed here",
      override: true
    )

    assert_equal false, result.success?
    assert_equal "shadow", website.reload.distillator_mode
    assert_includes result.errors, "Activate anyway is not allowed in this runtime"
  ensure
    Rails.unstub(:env)
  end

  test "activate anyway records override reason blockers and warnings" do
    website = build_website("shadow", seedurl: "override-record")
    url = "https://example.org/override-record"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:override-record", rdfs_class: rdfs_classes(:one))
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

    result = Distillator::RolloutTransition.call(
      website: website,
      to_mode: "active",
      actor: "test",
      reason: "Manual inspection complete",
      override: true
    )

    assert_equal true, result.success?
    event = website.rollout_events.order(:created_at).last
    assert_equal "Manual inspection complete", event.reason
    assert_equal true, event.readiness_snapshot["override"]
    assert_equal "rollout.override", event.readiness_snapshot["event"]
    assert_includes event.readiness_snapshot["warnings"], "Needs review: statements check is missing."
    assert_equal [], event.readiness_snapshot["blockers"]
  end

  test "activate anyway records current blockers when readiness is blocked" do
    website = Website.create!(
      name: "Tout Culture",
      seedurl: "outside-seed",
      graph_name: "https://example.org/outside-seed",
      default_language: "en",
      distillator_mode: "shadow"
    )
    url = "https://example.org/override-blockers"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:override-blockers", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true, "statement_count_delta_acceptable" => true },
      final_url: url
    )

    result = Distillator::RolloutTransition.call(
      website: website,
      to_mode: "active",
      actor: "test",
      reason: "Staging override",
      override: true
    )

    assert_equal true, result.success?
    event = website.rollout_events.order(:created_at).last
    assert_includes event.readiness_snapshot["blockers"], "Cannot activate yet: export check is missing."
  end

  private

  def build_website(mode, seedurl: "rollout-transition")
    Website.create!(
      name: "Rollout transition #{mode}",
      seedurl: seedurl,
      graph_name: "https://example.org/#{seedurl}",
      default_language: "en",
      distillator_mode: mode
    )
  end
end
