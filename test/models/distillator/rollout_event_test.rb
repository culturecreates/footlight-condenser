require "test_helper"

class Distillator::RolloutEventTest < ActiveSupport::TestCase
  test "requires a target mode" do
    event = Distillator::RolloutEvent.new(website: websites(:one))

    assert_not event.valid?
    assert_includes event.errors[:to_mode], "can't be blank"
  end
end
