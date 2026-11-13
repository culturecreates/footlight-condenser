require "test_helper"

class Distillator::Cohorts::RegistryTest < ActiveSupport::TestCase
  setup do
    Distillator::Cohorts::Registry.reload!
  end

  test "loads cohorts from yaml" do
    cohort = Distillator::Cohorts::Registry.fetch("lavitrine_pipeline")

    assert_equal "La Vitrine pipeline", cohort[:label]
    assert_includes cohort[:match_fields], "seedurl"
    assert_includes cohort[:match_fields], "name"
    assert_includes cohort[:match_fields], "code"
    assert_includes cohort[:feed_names], "hector-charland-com"
  end

  test "missing yaml fails safely with empty cohort list" do
    Distillator::Cohorts::Registry.stubs(:path).returns(Pathname.new("/tmp/distillator-cohorts-missing.yml"))
    Distillator::Cohorts::Registry.reload!

    assert_equal({}, Distillator::Cohorts::Registry.all)
    assert_nil Distillator::Cohorts::Registry.fetch("lavitrine_pipeline")
  ensure
    Distillator::Cohorts::Registry.unstub(:path)
    Distillator::Cohorts::Registry.reload!
  end
end
