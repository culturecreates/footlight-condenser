# test/test_helper.rb
require 'simplecov'
SimpleCov.start do
  enable_coverage_for_eval
  enable_coverage :branch
  add_filter %r{^/test/}
  add_group "Models", "app/models"
  add_group "Helpers", "app/helpers"
  add_group "Controllers", "app/controllers"
  add_group "Services", "app/services"
  add_group "Long files" do |src_file|
    src_file.lines.count > 100
  end
  add_group "Short files" do |src_file|
    src_file.lines.count < 10
  end
end

ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

# Disable verbose Ruby warnings (if you use $VERBOSE elsewhere, remove this)
$VERBOSE = nil

# -------------------------------
# Rails 6+ Parallel Testing Control
# -------------------------------
class ActiveSupport::TestCase
  # Always run with a single thread unless you have *completely* parallel-safe tests & fixtures.
  if respond_to?(:parallelize)
    parallelize(workers: 1)
  end

  # Rails 7+ fixture parallel loading (also disables for Rails 8)
  if respond_to?(:use_parallel_loading=)
    self.use_parallel_loading = false
  end

  # Load all fixtures in the correct order.
  fixtures :rdfs_classes,
           :properties,
           :search_exceptions,
           :websites,
           :webpages,
           :jsonld_outputs,
           :sources,
           :messages,
           :statements

  # Add your test support gems here (mocha, vcr, webmock, etc.)
  require 'mocha/minitest'
  require 'webmock'
  require 'vcr'

  VCR.configure do |config|
    config.cassette_library_dir = "test/vcr_cassettes"
    config.hook_into :webmock
    config.allow_http_connections_when_no_cassette = true
  end

  # Use transactional tests (recommended)
  self.use_transactional_tests = true

  # Add more helper methods to be used by all tests here...
end
