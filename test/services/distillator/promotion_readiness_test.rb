require "test_helper"

class Distillator::PromotionReadinessTest < ActiveSupport::TestCase
  test "la vitrine sites block promotion when export evidence is missing" do
    website = build_website(name: "Tout Culture", seedurl: "outside-seed")
    cache = build_cache(signals: { "representative_urls_checked" => true, "statement_count_delta_acceptable" => true })

    result = Distillator::PromotionReadiness.call(website: website, cache: cache)

    assert_includes result.blockers, "Cannot activate yet: export check is missing."
    assert_equal [], result.warnings
  end

  test "non cohort sites warn when export evidence is missing" do
    website = build_website(name: "Outside Feed", seedurl: "outside-feed")
    cache = build_cache(signals: { "representative_urls_checked" => true, "statement_count_delta_acceptable" => true })

    result = Distillator::PromotionReadiness.call(website: website, cache: cache)

    assert_equal [], result.blockers
    assert_includes result.warnings, "Needs review: export check is missing."
  end

  test "la vitrine sites pass when representative urls statement delta and export checks are present" do
    website = build_website(name: "Tout Culture", seedurl: "outside-seed")
    cache = build_cache(signals: {})
    website.transition_evidences.create!(
      url: "https://example.org/event",
      check_kind: "fetch_parity",
      status: "checked",
      details: { representative_urls_checked: true },
      checked_at: 1.hour.ago
    )
    website.transition_evidences.create!(
      url: "https://example.org/event",
      check_kind: "statement_delta",
      status: "checked",
      statement_count_delta_acceptable: true,
      checked_at: 1.hour.ago
    )
    website.transition_evidences.create!(
      url: "https://example.org/event",
      check_kind: "export_diff",
      status: "checked",
      export_diff_checked: true,
      checked_at: 1.hour.ago
    )

    result = Distillator::PromotionReadiness.call(website: website, cache: cache)

    assert_equal [], result.blockers
    assert_equal [], result.warnings
  end

  test "la vitrine sites block promotion when durable evidence is stale" do
    website = build_website(name: "Tout Culture", seedurl: "outside-seed")
    cache = build_cache(signals: {})
    website.transition_evidences.create!(
      url: "https://example.org/event",
      check_kind: "fetch_parity",
      status: "checked",
      details: { representative_urls_checked: true },
      checked_at: 2.days.ago
    )
    website.transition_evidences.create!(
      url: "https://example.org/event",
      check_kind: "statement_delta",
      status: "checked",
      statement_count_delta_acceptable: true,
      checked_at: 2.days.ago
    )
    website.transition_evidences.create!(
      url: "https://example.org/event",
      check_kind: "export_diff",
      status: "accepted",
      export_diff_checked: true,
      export_diff_accepted: true,
      checked_at: 8.days.ago
    )

    result = Distillator::PromotionReadiness.call(website: website, cache: cache)

    assert_includes result.blockers, "Cannot activate yet: export check is stale."
    assert_includes result.warnings, "Needs review: export check is stale."
  end

  private

  def build_website(name:, seedurl:)
    Website.create!(
      name: name,
      seedurl: seedurl,
      graph_name: "https://example.org/#{seedurl}",
      default_language: "en",
      distillator_mode: "shadow"
    )
  end

  def build_cache(signals:)
    Distillator::FetchCache.new(
      uri_key: CGI.escape("https://example.org/event"),
      normalized_url: "https://example.org/event",
      signals: signals
    )
  end
end
