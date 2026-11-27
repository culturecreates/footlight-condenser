require "test_helper"

class Distillator::TransitionCheckOptionsTest < ActiveSupport::TestCase
  test "old runs and absent options retain the default policy" do
    options = Distillator::TransitionCheckOptions.new
    assert options.default?
    assert_not options.strict?
    assert_equal({ "sample_mode" => "default", "strictness" => "standard" }, options.to_h)
    assert_equal 5, options.size_for(9, default: 5)
    assert_equal 2, options.size_for(2, default: 5)
    assert_raises(ArgumentError) { Distillator::TransitionCheckOptions.coerce(false) }
  end

  test "all pages and fixed counts are explicit rather than silently capped at 25" do
    all = Distillator::TransitionCheckOptions.new(sample_mode: "all", strictness: "strict")
    assert_equal 135, all.size_for(135, default: 25)
    assert all.strict?
    fixed = Distillator::TransitionCheckOptions.new(sample_mode: "count", sample_size: "050")
    assert_equal 50, fixed.size_for(135, default: 25)
    assert_equal 9, fixed.size_for(9, default: 5)
    assert_equal 0, fixed.size_for(0, default: 5)
  end

  test "invalid policies counts and shapes fail rather than silently reducing scope" do
    [[], "all", { sample_mode: "bogus" }, { strictness: "critical-only" }, { other: true },
      *[nil, "", "0", "-1", "1.5", "1001", "all"].map { |n| { sample_mode: "count", sample_size: n } }].each do |input|
      assert_raises(ArgumentError, input.inspect) { Distillator::TransitionCheckOptions.new(input) }
    end
  end

  test "irrelevant fixed count input does not alter an all or default request" do
    assert_equal Distillator::TransitionCheckOptions.new.to_h,
      Distillator::TransitionCheckOptions.new(sample_mode: "default", sample_size: "25").to_h
    assert_equal({ "sample_mode" => "all", "strictness" => "standard" },
      Distillator::TransitionCheckOptions.new(sample_mode: "all", sample_size: "25").to_h)
  end
end
