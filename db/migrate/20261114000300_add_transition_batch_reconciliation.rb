class AddTransitionBatchReconciliation < ActiveRecord::Migration[8.0]
  def change
    add_column :distillator_transition_batches, :last_reconciled_at, :datetime
  end
end
