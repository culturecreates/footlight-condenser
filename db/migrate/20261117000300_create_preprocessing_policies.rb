class CreatePreprocessingPolicies < ActiveRecord::Migration[8.0]
  def change
    create_table :preprocessing_policies do |t|
      t.bigint :statement_id, null: false
      t.bigint :website_id, null: false
      t.bigint :webpage_id, null: false
      t.bigint :source_id, null: false
      t.string :seedurl, null: false
      t.boolean :enabled, default: false, null: false
      t.boolean :inputs_verified, default: false, null: false
      t.boolean :monitoring_enabled, default: true, null: false
      t.integer :interval_hours, default: 12, null: false
      t.integer :stale_after_hours, default: 48, null: false
      t.jsonb :input_statement_ids, default: [], null: false
      t.datetime :next_due_at
      t.bigint :active_run_id
      t.datetime :lease_expires_at
      t.datetime :last_enqueued_at
      t.datetime :last_attempt_at
      t.datetime :last_success_at
      t.datetime :last_checked_at
      t.string :last_result
      t.text :last_error
      t.timestamps
    end
    add_index :preprocessing_policies, :statement_id, unique: true
    add_index :preprocessing_policies, [:enabled, :next_due_at]
    create_table :preprocessing_runs do |t|
      t.references :preprocessing_policy, null: false, foreign_key: true
      t.string :status, null: false
      t.string :configuration_digest, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :output_refreshed_at
      t.jsonb :input_observations, default: [], null: false
      t.text :error
      t.timestamps
    end
    add_column :monitoring_issues, :kind, :string, default: "dsl_error", null: false
    add_column :monitoring_issues, :preprocessing_policy_id, :bigint
    add_index :monitoring_issues, [:preprocessing_policy_id, :kind]
  end
end
