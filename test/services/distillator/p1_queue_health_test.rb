require "test_helper"

class Distillator::P1QueueHealthTest < ActiveSupport::TestCase
  Worker = Struct.new(:queues, :attributes) do
    def [](key) = attributes[key]
  end

  test "only a fresh worker consuming the transition queue establishes health" do
    now = Time.current
    worker = Worker.new([Distillator::TransitionCheckJob.new.queue_name], { "beat" => now.to_f, "quiet" => "false" })
    assert Distillator::TransitionQueueHealth.call(adapter: "sidekiq", processes: [worker], now: now).ok?
    assert_not Distillator::TransitionQueueHealth.call(adapter: "sidekiq", processes: [], now: now).ok?
    worker.attributes["beat"] = (now - 2.minutes).to_f
    assert_not Distillator::TransitionQueueHealth.call(adapter: "sidekiq", processes: [worker], now: now).ok?
    worker.attributes.merge!("beat" => now.to_f, "quiet" => "true")
    assert_not Distillator::TransitionQueueHealth.call(adapter: "sidekiq", processes: [worker], now: now).ok?
    worker.attributes["quiet"] = "false"
    worker.queues = ["other"]
    assert_not Distillator::TransitionQueueHealth.call(adapter: "sidekiq", processes: [worker], now: now).ok?
  end

  test "Redis errors are reported without exposing connection credentials" do
    Distillator::TransitionQueueHealth::Result # autoload before stubbing dependency
    Sidekiq::ProcessSet.stubs(:new).raises(RuntimeError, "redis://secret@example.org")
    result = Distillator::TransitionQueueHealth.call(adapter: "sidekiq")
    assert_not result.ok?
    assert_includes result.message, "Queue health unavailable"
    assert_not_includes result.message, "secret"
  end
end
