Sidekiq.configure_server do |config|
  config.redis = { ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE } }

  # Sidekiq's recurring heartbeat restarts this sweep after worker restarts and
  # queue outages. Do not depend on a job scheduling its own successor.
  next_sweep_at = 0
  quiet = false
  config.on(:quiet) { quiet = true }
  config.on(:beat) do
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if !quiet && now >= next_sweep_at
      Rails.application.executor.wrap do
        job = Distillator::TransitionBatchReconcileJob.perform_later
        next_sweep_at = now + 60 if job
      end
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE } }
end
