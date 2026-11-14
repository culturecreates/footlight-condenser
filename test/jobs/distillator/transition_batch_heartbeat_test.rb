require "test_helper"
require "sidekiq"

class Distillator::TransitionBatchHeartbeatTest < ActiveJob::TestCase
  class WorkerConfig
    attr_writer :redis
    attr_reader :hooks
    def initialize
      @hooks = {}
    end
    def on(event, &block)
      @hooks[event] = block
    end
  end

  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @config = WorkerConfig.new
    Sidekiq.stubs(:configure_server).yields(@config)
    Sidekiq.stubs(:configure_client).yields(@config)
    load Rails.root.join("config/initializers/sidekiq.rb")
  end
  teardown { ActiveJob::Base.queue_adapter = @old_adapter }

  test "worker heartbeat independently schedules sweeps and stops scheduling when quiet" do
    Process.stubs(:clock_gettime).returns(10.0)
    assert_enqueued_with(job: Distillator::TransitionBatchReconcileJob) { @config.hooks.fetch(:beat).call }
    assert_no_enqueued_jobs { @config.hooks.fetch(:beat).call }
    Process.stubs(:clock_gettime).returns(71.0)
    assert_enqueued_with(job: Distillator::TransitionBatchReconcileJob) { @config.hooks.fetch(:beat).call }
    @config.hooks.fetch(:quiet).call
    Process.stubs(:clock_gettime).returns(132.0)
    assert_no_enqueued_jobs { @config.hooks.fetch(:beat).call }
  end

  test "a declined sweep enqueue is retried on the next heartbeat" do
    Process.stubs(:clock_gettime).returns(10.0)
    Distillator::TransitionBatchReconcileJob.expects(:perform_later).returns(false)
    @config.hooks.fetch(:beat).call
    Distillator::TransitionBatchReconcileJob.unstub(:perform_later)
    assert_enqueued_with(job: Distillator::TransitionBatchReconcileJob) { @config.hooks.fetch(:beat).call }
  end
end
