module Distillator
  class SiteTransitionWatchdogJob < ApplicationJob
    queue_as :default

    def perform(id)
      item = SiteTransition.find_by(id: id)
      return unless item && !item.terminal? && item.deadline_at
      if item.deadline_at > Time.current
        self.class.set(wait_until: item.deadline_at).perform_later(id)
      else
        SiteTransitionProcessor.new.recover(item, reason: "The workflow expired or its worker stopped before verification completed.", token: item.phase_token)
      end
    end
  end
end
