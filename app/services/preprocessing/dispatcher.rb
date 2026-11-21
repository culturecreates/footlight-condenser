module Preprocessing
  class Dispatcher
    QUEUED_LEASE = 2.hours

    def self.call
      PreprocessingPolicy.enabled_policies.find_each do |policy|
        dispatch(policy)
      rescue StandardError => error
        Rails.logger.error("[Preprocessing] Dispatch failed policy=#{policy.id} #{error.class}")
      end
      Monitor.call
    end

    def self.dispatch(policy, force: false)
      run = nil
      policy.with_lock do
        return unless policy.enabled?
        now = Time.current
        return if policy.active_run_id && policy.lease_expires_at && policy.lease_expires_at > now
        if policy.active_run_id
          policy.runs.where(id: policy.active_run_id, status: %w[queued running]).update_all(
            status: "interrupted", finished_at: now, error: "Execution lease expired; refresh rescheduled")
          policy.next_due_at = now
          policy.last_result = "failed"
          policy.last_error = "Previous execution lease expired; refresh rescheduled"
        end
        policy.active_run_id = nil
        policy.lease_expires_at = nil
        if !force && policy.next_due_at && policy.next_due_at > now
          policy.save!
          return
        end
        run = policy.runs.create!(status: "queued", configuration_digest: policy.configuration_digest)
        policy.update!(active_run_id: run.id, lease_expires_at: now + QUEUED_LEASE, last_enqueued_at: now)
      end
      begin
        job = RefreshPreprocessingStatementJob.perform_later(policy.id, run.id)
        raise "Queue rejected preprocessing job" unless job
      rescue StandardError => error
        policy.with_lock do
          if policy.active_run_id == run.id
            run.update!(status: "enqueue_failed", error: error.class.name, finished_at: Time.current)
            policy.update!(active_run_id: nil, lease_expires_at: nil, last_result: "failed", last_error: "Could not enqueue refresh: #{error.class}")
          end
        end
        raise
      end
      run
    end
  end
end
