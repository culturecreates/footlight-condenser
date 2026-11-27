class AddWorkflowActionToTransitionBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :distillator_transition_batches, :workflow_action, :string, default: "verify", null: false
    change_column_default :distillator_transition_batches, :workflow_action, from: "verify", to: "validate"
  end
end
