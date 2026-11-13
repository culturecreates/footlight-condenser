require "test_helper"
require_relative "../../support/distillator_fixture_helpers"

class Distillator::FixtureHelpersTest < ActiveSupport::TestCase
  include DistillatorFixtureHelpers

  test "fixture helper exposes representative migration categories" do
    assert_equal 10, distillator_fixture_categories.length
    assert_equal true, File.exist?(distillator_fixture_path(:simple_static_html_title))
    assert_equal true, File.exist?(distillator_fixture_path(:json_post_legacy_only))
    assert_equal true, File.exist?(distillator_fixture_path(:render_js_legacy_only))
  end
end
