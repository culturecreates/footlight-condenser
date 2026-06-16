require 'test_helper'

class ExportGraphToDatabusTest < ActiveSupport::TestCase

  test "check schedule" do
    BatchJobsController.any_instance.stubs(:refresh_upcoming_events_jobs)
    BatchJobsController.any_instance.stubs(:check_for_new_webpages_jobs)

    job_proxy = mock("export_to_artsdata_job_proxy")
    job_proxy.stubs(:perform_later)
    ExportToArtsdataJob.stubs(:set).returns(job_proxy)

    ExportGraphToDatabus.check_schedule('http://localhost:3000')
  end

end
