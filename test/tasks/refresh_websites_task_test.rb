require "test_helper"
require "rake"

class RefreshWebsitesTaskTest < ActiveSupport::TestCase
  setup do
    @previous_callback_url = ENV["ARTSDATA_CALLBACK_BASE_URL"]
    Rails.application.load_tasks unless Rake::Task.task_defined?("footlight:refresh_websites")
    @task = Rake::Task["footlight:refresh_websites"]
    @task.reenable
  end

  teardown do
    ENV["ARTSDATA_CALLBACK_BASE_URL"] = @previous_callback_url
  end

  test "the scheduler task forwards the configured callback origin" do
    ENV["ARTSDATA_CALLBACK_BASE_URL"] = "https://staging.example.org"
    ExportGraphToDatabus.expects(:check_schedule).with("https://staging.example.org")

    @task.invoke
  end

  test "the scheduler task defaults to the existing production callback" do
    ENV.delete("ARTSDATA_CALLBACK_BASE_URL")
    ExportGraphToDatabus.expects(:check_schedule).with("https://footlight-condenser.herokuapp.com")

    @task.invoke
  end
end
