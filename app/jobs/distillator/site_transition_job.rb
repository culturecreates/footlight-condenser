module Distillator
  class SiteTransitionJob < ApplicationJob
    queue_as :default

    def perform(id, phase:)
      SiteTransitionProcessor.new.perform(id, phase: phase)
    end
  end
end
