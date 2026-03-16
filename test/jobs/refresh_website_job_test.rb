require 'test_helper'

class RefreshWebpageJobTest < ActiveJob::TestCase
  test "perform delegates refresh to service object" do
    webpage = webpages(:six)
    service = mock("refresh_service")

    RefreshWebpageJob.any_instance.stubs(:wringer_received_404?).returns(false)
    service.expects(:call).with(
      webpage: webpage,
      default_language: webpage.website.default_language,
      scrape_options: { force_scrape_every_hrs: 1 }
    ).returns([])

    Statements::RefreshWebpageStatementsService
      .expects(:new)
      .with(refresh_helper: ApplicationController.helpers)
      .returns(service)

    RefreshWebpageJob.perform_now(webpage.url)
  end
end
