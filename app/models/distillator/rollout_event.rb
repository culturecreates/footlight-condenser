module Distillator
  class RolloutEvent < ApplicationRecord
    self.table_name = "distillator_rollout_events"

    belongs_to :website

    validates :to_mode, presence: true
  end
end
