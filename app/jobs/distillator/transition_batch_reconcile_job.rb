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
    end
  end
end
