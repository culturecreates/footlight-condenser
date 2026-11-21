class CreateTransitionBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :distillator_transition_batches do |t|
      t.string :request_key, null: false
      t.string :selection_context
      t.datetime :stopped_at
      t.jsonb :check_options, null: false, default: { sample_mode: "all", strictness: "strict" }
      t.timestamps
    end
    add_index :distillator_transition_batches, :request_key, unique: true
    create_table :distillator_site_transitions do |t|
      t.references :batch, null: false, foreign_key: { to_table: :distillator_transition_batches }
      t.references :website, foreign_key: { on_delete: :nullify }
      t.references :pre_run, foreign_key: { to_table: :distillator_transition_runs, on_delete: :nullify }
      t.references :post_run, foreign_key: { to_table: :distillator_transition_runs, on_delete: :nullify }
      t.string :website_name, null: false
      t.string :seedurl
      t.integer :position, null: false
      t.string :status, null: false, default: "queued"
      t.string :phase, null: false, default: "queued"
      t.string :initial_mode, null: false
      t.string :expected_mode, null: false
      t.bigint :expected_event_id
      t.string :phase_token
      t.datetime :started_at
      t.datetime :phase_started_at
      t.datetime :deadline_at
      t.datetime :completed_at
      t.string :final_mode
      t.string :final_backend
      t.text :reason
      t.jsonb :phase_results, null: false, default: {}
      t.integer :estimated_seconds
      t.timestamps
    end
    add_index :distillator_site_transitions, :website_id, unique: true,
      where: "status IN ('queued', 'running')", name: "one_active_site_transition"
    add_index :distillator_site_transitions, [:batch_id, :position], unique: true
    add_column :distillator_transition_runs, :progress, :jsonb, null: false, default: {}
  end
end
