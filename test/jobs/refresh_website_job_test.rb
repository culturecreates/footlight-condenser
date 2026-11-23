require 'test_helper'

class RefreshWebpageJobTest < ActiveJob::TestCase
  test "perform delegates refresh to service object" do
    webpage = webpages(:six)
    Distillator::WebpageRemovalCandidate.stubs(:call).returns(
      Distillator::WebpageRemovalCandidate::Result.new(delete: false, reason: :missing_cache)
    )

    Distillator::RefreshRunner.expects(:call).with(
      webpage: webpage,
      refresh_helper: ApplicationController.helpers,
      scrape_options: {}
    ).returns([])

    RefreshWebpageJob.perform_now(webpage.url)
  end

  test "perform destroys webpage when the removal policy authorizes it" do
    webpage = webpages(:six)
    Distillator::RefreshRunner.stubs(:call).returns([])
    Distillator::WebpageRemovalCandidate.stubs(:call).returns(
      Distillator::WebpageRemovalCandidate::Result.new(delete: true, reason: :delete_candidate)
    )

    assert_difference("Webpage.count", -1) do
      RefreshWebpageJob.perform_now(webpage.url)
    end
  end

  test "old listing-redirect cache flags cannot authorize webpage deletion" do
    webpage = webpages(:six)
    key = Distillator::WringerUrlKey.call(webpage.url)
    cache = Distillator::FetchCache.create!(uri_key: key.uri_key, normalized_url: key.normalized_url,
      http_response_code: 200, final_url: "https://example.org/events/", scrape_date: Time.current)
    Distillator::RefreshRunner.stubs(:call).returns([])

    %w[redirect_to_listing redirect_to_listing_legacy_body].each do |issue|
      cache.update_columns(primary_issue_key: issue, delete_candidate: true,
        signals: { "primary_issue_key" => issue, "primary_issue_delete" => true })
      assert_no_difference("Webpage.count") { RefreshWebpageJob.perform_now(webpage.id) }
      assert Webpage.exists?(webpage.id)
    end
  end

  test "perform preserves scrape options through refresh runner" do
    webpage = webpages(:six)
    Distillator::WebpageRemovalCandidate.stubs(:call).returns(
      Distillator::WebpageRemovalCandidate::Result.new(delete: false, reason: :missing_cache)
    )

    Distillator::RefreshRunner.expects(:call).with(
      webpage: webpage,
      refresh_helper: ApplicationController.helpers,
      scrape_options: {
        force_scrape: true,
        force_scrape_every_hrs: 0,
        render_js: true,
        use_phantomjs: true,
        json_post: true,
        absolute_src: true,
        include_fragment: true
      }
    ).returns([])

    RefreshWebpageJob.perform_now(
      webpage.url,
      {
        force_scrape: true,
        force_scrape_every_hrs: 0,
        render_js: true,
        use_phantomjs: true,
        json_post: true,
        absolute_src: true,
        include_fragment: true
      }
    )
  end
end
