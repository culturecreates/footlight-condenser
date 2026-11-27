require "sidekiq/api"

module Distillator
  class TransitionQueueHealth
    Result = Struct.new(:ok?, :message, keyword_init: true)

    def self.call(adapter: ActiveJob::Base.queue_adapter_name.to_s, processes: nil, now: Time.current)
      unless adapter == "sidekiq"
        local = Rails.env.test? && adapter.in?(%w[test inline])
        return Result.new(ok?: local, message: local ? "Test adapter (worker not required)" : "No monitored Sidekiq worker (adapter: #{adapter})")
      end
      # ProcessSet reads Redis heartbeat data; constructing it without cleanup is read-only.
      workers = processes || Sidekiq::ProcessSet.new(false)
      queue = Distillator::TransitionCheckJob.new.queue_name
      alive = workers.any? do |worker|
        Array(worker.queues).include?(queue) && worker["beat"].to_f > now.to_f - 60 && worker["quiet"].to_s != "true"
      end
      Result.new(ok?: alive, message: alive ? "Redis reachable; live worker consumes #{queue}" : "Redis reachable; no live worker consumes #{queue}")
    rescue StandardError => error
      Result.new(ok?: false, message: "Queue health unavailable (#{error.class.name}). Check Redis and the worker.")
    end
  end
end
