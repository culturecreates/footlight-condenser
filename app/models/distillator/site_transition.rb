module Distillator
  class SiteTransition < ApplicationRecord
    self.table_name = "distillator_site_transitions"
    TERMINAL = %w[passed attention cancelled recovery_failed].freeze
    belongs_to :batch, class_name: "Distillator::TransitionBatch"
    belongs_to :website, optional: true
    belongs_to :pre_run, class_name: "Distillator::TransitionRun", optional: true
    belongs_to :post_run, class_name: "Distillator::TransitionRun", optional: true
    scope :active, -> { where(status: %w[queued running]) }
    validates :status, inclusion: { in: %w[queued running] + TERMINAL }
    validates :phase, inclusion: { in: %w[queued precheck postcheck finished] }

    def terminal?
      status.in?(TERMINAL)
    end

    def request_cancellation!
      return false unless website

      website.with_lock do
        with_lock do
          next false unless status == "running"

          update!(cancel_requested_at: Time.current) unless cancel_requested_at?
          true
        end
      end
    end

    def check_cancellation!
      requested = self.class.uncached { self.class.where(id: id).pick(:cancel_requested_at) }
      raise TransitionRun::Cancelled, TransitionRun::CANCELLED_MESSAGE if requested
    end

    def current_run
      phase == "postcheck" ? post_run : pre_run
    end

    def actor
      "transition-workflow:#{id}"
    end
  end
end
