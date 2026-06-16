module Distillator
  class TransitionCheckJob < ApplicationJob
    queue_as :default

    def perform(website_id)
      Distillator::TransitionCheckRunner.call(website: website_id)
    end
  end
end
