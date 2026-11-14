class CreateDistillatorTransitionExclusions < ActiveRecord::Migration[8.0]
  def change
    create_table :distillator_transition_exclusions do |t|
      t.references :website, null: false, foreign_key: true
      t.references :source_run, null: false, foreign_key: { to_table: :distillator_transition_runs }
      t.text :url, null: false
      t.text :reason, null: false
      t.jsonb :recorded_evidence, null: false, default: {}
      t.datetime :revoked_at
      t.text :revocation_reason
      t.timestamps
    end
    add_index :distillator_transition_exclusions, [:website_id, :url], unique: true,
      where: "revoked_at IS NULL", name: "idx_transition_exclusions_active_url"
  end
end
