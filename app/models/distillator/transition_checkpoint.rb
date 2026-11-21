module Distillator
  class TransitionCheckpoint < ApplicationRecord
    self.table_name = "distillator_transition_checkpoints"
    belongs_to :transition_run, class_name: "Distillator::TransitionRun", foreign_key: :transition_run_id
  end
end
