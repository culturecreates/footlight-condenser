require "test_helper"
require "rake"

class DistillatorCacheTaskTest < ActiveSupport::TestCase
  setup do
    Distillator::FetchCache.delete_all
    Rails.application.load_tasks unless Rake::Task.task_defined?("distillator:cache:backfill_health")
    @task = Rake::Task["distillator:cache:backfill_health"]
    @task.reenable
  end

  test "backfill task populates materialized health fields for old rows" do
    cache = Distillator::FetchCache.create!(
      uri_key: CGI.escape("http://example.org/backfill"),
      normalized_url: "http://example.org/backfill",
      html: "<html>cached</html>",
      body: "<html>cached</html>",
      scrape_date: 2.days.ago,
      successful_refresh: 2.days.ago,
      http_response_code: 200,
      headers: {},
      signals: { "network_status" => "ok", "content_type" => "html" },
      hints: []
    )
    cache.update_columns(
      health_status: nil,
      health_severity: nil,
      health_reasons: [],
      html_bytes: 0,
      body_bytes: 0,
      redirected: false,
      network_status: nil,
      content_type: nil,
      hint_keys: []
    )

    @task.invoke
    cache.reload

    assert_equal "healthy", cache.health_status
    assert_equal "ok", cache.health_severity
    assert_equal "<html>cached</html>".bytesize, cache.html_bytes
    assert_equal "ok", cache.network_status
    assert_equal "html", cache.content_type
  end
end
