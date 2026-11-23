require "test_helper"

class Distillator::TransitionFetchSlotTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "shares a slot across the source host and its www alias on separate connections" do
    Distillator::TransitionFetchSlot.call(uri: "https://www.Example.org/event") do
      same_host, other_host = Thread.new do
        [
          Distillator::TransitionFetchSlot.call(uri: "https://example.org/another") { :acquired },
          Distillator::TransitionFetchSlot.call(uri: "https://other.example/another") { :acquired }
        ]
      end.value

      assert_nil same_host
      assert_equal :acquired, other_host
    end
    assert_equal :acquired, Thread.new { Distillator::TransitionFetchSlot.call(uri: "https://example.org/event") { :acquired } }.value
  end

  test "releases the slot when the fetch fails and respects the check budget" do
    url = "https://example.org/event"
    assert_raises(RuntimeError) do
      Distillator::TransitionFetchSlot.call(uri: url) { raise "interrupted" }
    end

    assert_equal :acquired, Thread.new { Distillator::TransitionFetchSlot.call(uri: url) { :acquired } }.value
    assert_nil Distillator::TransitionFetchSlot.call(uri: url, wait_allowed: -> { false }) { flunk "check already stopped" }
  end
end
