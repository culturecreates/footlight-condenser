module Distillator
  # Independently scheduled from the worker heartbeat: there is no continuation
  # enqueue gap that can permanently strand a committed batch.
  class TransitionBatchReconcileJob < ApplicationJob
    queue_as :default

    def perform
      TransitionBatch.where(id: SiteTransition.active.select(:batch_id)).find_each do |batch|
        batch.reconcile!
      rescue StandardError => error
        # An unavailable queue or one damaged group must not stop other groups.
        Rails.logger.warn(event: "distillator.batch.reconcile_failed", id: batch.id, error_class: error.class.name)
      end
      recover_interrupted_runs
    end

    private

    def recover_interrupted_runs
      TransitionRun.guarded_running.find_each do |run|
        run.recover_interrupted! do
          workflow = SiteTransition.active.find_by(pre_run_id: run.id) || SiteTransition.active.find_by(post_run_id: run.id)
          if run.resumable? && run.requested_at > Time.current - TransitionRun::LEASE
            if workflow && workflow.current_run&.id == run.id
              SiteTransitionJob.perform_later(workflow.id, phase: workflow.phase)
            elsif !workflow
              TransitionCheckJob.perform_later(run.website_id, run_id: run.id)
            end
            next
          end
          reason = "The worker stopped before the transition check finished. Retry with the same options."
          if workflow && workflow.current_run&.id == run.id
            SiteTransitionProcessor.new.recover(workflow, reason: reason, token: workflow.phase_token)
          elsif !workflow
            run.fail!(reason)
          end
        end
      rescue StandardError => error
        Rails.logger.warn(event: "distillator.transition.recovery_failed", run_id: run.id, error_class: error.class.name)
      end
    end
  end
end
