class CreateDistillatorTransitionCheckpoints < ActiveRecord::Migration[8.0]
  def change
    create_table :distillator_transition_checkpoints do |t|
      t.references :transition_run, null: false, index: false,
        foreign_key: { to_table: :distillator_transition_runs, on_delete: :cascade }
      t.integer :offset, null: false
      t.integer :page_count, null: false
      t.jsonb :payload, null: false
    end
    add_index :distillator_transition_checkpoints, [:transition_run_id, :offset], unique: true,
      name: "index_transition_checkpoints_on_run_and_offset"
  end
end
