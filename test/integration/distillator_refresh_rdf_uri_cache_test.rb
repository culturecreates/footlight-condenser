require "test_helper"

class DistillatorRefreshRdfUriCacheTest < ActionDispatch::IntegrationTest
  setup do
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    Distillator::FetchCache.delete_all
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
  end

  test "refresh_rdf_uri with force_scrape_every_hrs writes raw distillator cache and refreshes statement cache" do
    webpage = webpages(:culture3r_refresh_fixture)
    webpage.website.update!(distillator_mode: "active")
    statement = statements(:culture3r_refresh_statement)
    previous_refreshed = statement.cache_refreshed
    previous_changed = statement.cache_changed
    html = "<html><body><h1>Gabrielle Caron Rodage</h1></body></html>"

    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::FetchGuard.stubs(:check_response).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::NativeFetch.expects(:call).once.returns(
      status: :ok,
      body: html,
      raw_body: html,
      headers: { content_type: "text/html" },
      final_url: webpage.url,
      redirect_chain: [webpage.url],
      wringer: { signals: {}, hints: [] },
      http_code: 200
    )

    patch refresh_rdf_uri_statements_path(format: :json), params: {
      rdf_uri: webpage.rdf_uri,
      force_scrape_every_hrs: "1"
    }

    assert_response :success
    statement.reload
    cache = Distillator::FetchCache.find_by(normalized_url: webpage.url)

    assert_equal "Gabrielle Caron Rodage", statement.cache
    assert_operator statement.cache_refreshed, :>, previous_refreshed
    assert_operator statement.cache_changed, :>, previous_changed
    assert cache.present?, "expected Distillator::FetchCache for #{webpage.url}"
    assert_equal html, cache.html
    assert_equal html, cache.body
    assert_equal 200, cache.http_response_code
    assert_equal [webpage.url], cache.redirect_chain
    assert_equal({ "content_type" => "text/html" }, cache.headers)
    assert_operator cache.scrape_date, :>, Time.zone.parse("2026-04-20 16:46:00 UTC")
    assert_operator cache.successful_refresh, :>, Time.zone.parse("2026-04-20 16:46:00 UTC")
  end
end
