module Distillator
  class TransitionCheckJob < ApplicationJob
    queue_as :default

    def perform(website_id, run_id: nil)
      website = Website.find(website_id)
      run = run_id ? website.transition_runs.find(run_id) : Distillator::TransitionRun.request!(website: website).run
      run.execute { Distillator::TransitionCheckRunner.call(website: website, transition_run: run) }
    end
  end
end
