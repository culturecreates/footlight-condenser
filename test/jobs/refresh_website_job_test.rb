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

  test "perform destroys webpage when latest distillator fetch cache is 404" do
    webpage = webpages(:six)
    Distillator::RefreshRunner.stubs(:call).returns([])
    Distillator::WebpageRemovalCandidate.stubs(:call).returns(
      Distillator::WebpageRemovalCandidate::Result.new(delete: true, reason: :delete_candidate)
    )

    assert_difference("Webpage.count", -1) do
      RefreshWebpageJob.perform_now(webpage.url)
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
