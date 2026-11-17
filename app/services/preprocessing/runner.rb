require "timeout"

module Preprocessing
  class Runner
    LeaseLost = Class.new(StandardError)
    RefreshFailed = Class.new(StandardError)
    MAX_RUNTIME = 5.minutes
    RUNNING_LEASE = 15.minutes

    def self.call(policy_id, run_id, helper: ApplicationController.helpers)
      policy = PreprocessingPolicy.find(policy_id)
      run = policy.runs.find(run_id)
      started = false
      policy.with_lock do
        return unless policy.active_run_id == run.id && run.status == "queued"
        unless policy.enabled? && run.configuration_digest == policy.configuration_digest
          run.update!(status: "skipped", error: "Policy disabled or configuration changed", finished_at: Time.current)
          policy.update!(active_run_id: nil, lease_expires_at: nil, last_result: "skipped")
          return
        end
        now = Time.current
        run.update!(status: "running", started_at: now, input_observations: policy.input_observations)
        policy.update!(last_attempt_at: now, lease_expires_at: now + RUNNING_LEASE, last_result: "running")
        started = true
      end
      begin
        raise RefreshFailed, policy.identity_error if policy.identity_error
        statement = policy.target
        Timeout.timeout(MAX_RUNTIME) do
          # Save statement data and completion together. A superseded worker
          # rolls back its writes when it discovers that its lease was replaced.
          Statement.transaction(requires_new: true) do
            statement.lock!
            statement.reload
            raise RefreshFailed, policy.identity_error(statement) if policy.identity_error(statement)
            raise RefreshFailed, "Manual reviewed statement was skipped; no recomputation occurred" if statement.manual && %w[ok updated].include?(statement.status)
            result = helper.refresh_statement_helper(statement)
            errors = Array(result[:errors]) + statement.errors.full_messages
            raise RefreshFailed, errors.first(3).join("; ") if errors.any?
            raise RefreshFailed, "Refresh returned without saving a new successful result" unless result[:saved] == true
            statement.reload
            raise RefreshFailed, "Stored refresh timestamp was not advanced to this attempt" unless statement.cache_refreshed && statement.cache_refreshed >= run.started_at
            policy.with_lock do
              raise LeaseLost unless policy.active_run_id == run.id && policy.enabled? && policy.configuration_digest == run.configuration_digest
              now = Time.current
              run.update!(status: "succeeded", finished_at: now, output_refreshed_at: statement.cache_refreshed)
              policy.update!(active_run_id: nil, lease_expires_at: nil, last_result: "succeeded", last_error: nil,
                last_success_at: statement.cache_refreshed, next_due_at: now + policy.interval_hours.hours)
            end
          end
        end
      rescue LeaseLost
        # Its statement writes have rolled back. Never complete a replacement.
        policy.with_lock do
          if policy.active_run_id == run.id
            run.update!(status: "skipped", finished_at: Time.current, error: "Policy changed during execution; result rolled back")
            policy.update!(active_run_id: nil, lease_expires_at: nil, last_result: "skipped")
          end
        end
      rescue StandardError => error
        policy.with_lock do
          if policy.active_run_id == run.id
            message = "#{error.class}: #{error.message}".encode("UTF-8", invalid: :replace, undef: :replace).squish.first(1000)
            run.update!(status: "failed", finished_at: Time.current, error: message)
            policy.update!(active_run_id: nil, lease_expires_at: nil, last_result: "failed", last_error: message,
              next_due_at: Time.current + 1.hour)
          end
        end
      ensure
        Monitor.evaluate(policy.reload) if started
      end
    end
  end
end
