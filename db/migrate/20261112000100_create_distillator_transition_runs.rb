class CreateDistillatorTransitionRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :distillator_transition_runs do |t|
      t.references :website, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.string :configuration_digest, null: false
      t.datetime :requested_at, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.timestamps
    end
    add_index :distillator_transition_runs, :website_id, unique: true,
      where: "status IN ('queued', 'running')", name: "one_active_transition_run_per_website"
    add_reference :distillator_transition_evidence, :transition_run,
      foreign_key: { to_table: :distillator_transition_runs }
  end
end
