class AddCheckOptionsToDistillatorTransitionRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :distillator_transition_runs, :check_options, :jsonb, default: {}, null: false
  end
end
