require "test_helper"
require "rake"

# class ExportArtsdataTaskTest < ActiveSupport::TestCase
#   setup do
#     Rails.application.load_tasks unless Rake::Task.task_defined?("export:artsdata")
#     @task = Rake::Task["export:artsdata"]
#     @output_dir = Rails.root.join("data", "migration_baseline")
#     @output_path = @output_dir.join("example_org.jsonld")
#     FileUtils.rm_f(@output_path)
#     ENV["seedurl"] = nil
#     ENV["SEEDURL"] = nil
#   end

#   teardown do
#     @task.reenable
#     FileUtils.rm_f(@output_path)
#     ENV["seedurl"] = nil
#     ENV["SEEDURL"] = nil
#   end

#   test "exports raw jsonld to deterministic baseline path" do
#     seedurl = "example.org"
#     jsonld = '[{"@id":"http://kg.footlight.io/resource/event-1"}]'

#     ExportArtsdataService.expects(:call).with(seedurl: seedurl).twice.returns(jsonld)

#     ENV["seedurl"] = seedurl
#     @task.invoke
#     first = File.read(@output_path)

#     @task.reenable
#     @task.invoke
#     second = File.read(@output_path)

#     assert_equal jsonld, first
#     assert_equal first, second
#   end

#   test "raises when seedurl is missing" do
#     error = assert_raises(ArgumentError) { @task.invoke }
#     assert_match("Missing seedurl", error.message)
#   end
# end
