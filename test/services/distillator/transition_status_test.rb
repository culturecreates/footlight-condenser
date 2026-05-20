require "test_helper"

class Distillator::TransitionStatusTest < ActiveSupport::TestCase
  test "no cache or evidence returns not checked" do
    website = build_website("Outside Feed", "outside-feed")

    status = Distillator::TransitionStatus.call(website: website, cache: nil)

    assert_equal :not_checked, status.status
    assert_equal :missing, status.fetch
    assert_equal :missing, status.statements
    assert_equal :missing, status.export
  end

  test "failed transport returns blocked and fetch failed" do
    website = build_website("Outside Feed", "outside-feed")
    cache = build_cache(signals: { "transport_success" => false, "content_success" => true }, health_status: "attempt_failed")

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :blocked, status.status
    assert_equal :failed, status.fetch
  end

  test "failed content returns blocked and fetch failed" do
    website = build_website("Outside Feed", "outside-feed")
    cache = build_cache(signals: { "transport_success" => true, "content_success" => false }, health_status: "attempt_failed")

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :blocked, status.status
    assert_equal :failed, status.fetch
  end

  test "la vitrine missing statement evidence returns blocked" do
    website = build_website("Tout Culture", "outside-seed")
    cache = build_cache(signals: { "transport_success" => true, "content_success" => true, "export_diff_checked" => true })

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :blocked, status.status
    assert_equal :missing, status.statements
  end

  test "la vitrine missing export evidence returns blocked" do
    website = build_website("Tout Culture", "outside-seed")
    cache = build_cache(signals: { "transport_success" => true, "content_success" => true, "statement_count_delta_acceptable" => true })

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :blocked, status.status
    assert_equal :missing, status.export
  end

  test "la vitrine cache signals alone do not satisfy statements and export checks" do
    website = build_website("Tout Culture", "outside-seed")
    cache = build_cache(
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "statement_count_delta_acceptable" => true,
        "export_diff_checked" => true
      }
    )

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :blocked, status.status
    assert_equal :missing, status.statements
    assert_equal :missing, status.export
  end

  test "ordinary missing export evidence returns review" do
    website = build_website("Outside Feed", "outside-feed")
    cache = build_cache(signals: { "transport_success" => true, "content_success" => true, "statement_count_delta_acceptable" => true })

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :review, status.status
    assert_equal :missing, status.export
  end

  test "ordinary sites still fall back to cache signals for statements and export" do
    website = build_website("Outside Feed", "outside-feed")
    cache = build_cache(
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "statement_count_delta_acceptable" => true,
        "export_diff_checked" => true
      }
    )

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :ready, status.status
    assert_equal :passed, status.statements
    assert_equal :passed, status.export
  end

  test "all required fresh evidence returns ready" do
    website = build_website("Tout Culture", "outside-seed")
    cache = build_cache(signals: { "transport_success" => true, "content_success" => true })
    website.transition_evidences.create!(url: "https://example.org/event", check_kind: "statement_delta", status: "checked", statement_count_delta_acceptable: true, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: "https://example.org/event", check_kind: "export_diff", status: "checked", export_diff_checked: true, checked_at: 1.hour.ago)

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :ready, status.status
    assert_equal :passed, status.fetch
    assert_equal :passed, status.statements
    assert_equal :passed, status.export
  end

  private

  def build_website(name, seedurl)
    Website.create!(
      name: name,
      seedurl: seedurl,
      graph_name: "https://example.org/#{seedurl}",
      default_language: "en",
      distillator_mode: "shadow"
    )
  end

  def build_cache(signals:, health_status: "healthy")
    Distillator::FetchCache.new(
      uri_key: CGI.escape("https://example.org/event"),
      normalized_url: "https://example.org/event",
      signals: signals,
      health_status: health_status,
      successful_refresh: 1.hour.ago,
      scrape_date: 1.hour.ago
    )
  end
end
