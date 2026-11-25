class CreateDistillatorMigrationBaselines < ActiveRecord::Migration[8.0]
  def up
    create_table :distillator_migration_baselines do |t|
      t.references :website, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.bigint :validation_run_id, null: false
      t.jsonb :validation_run_ids, null: false
      t.datetime :validated_at, null: false
      t.string :configuration_digest, null: false
      t.string :configuration_fingerprint, null: false
      t.jsonb :page_fingerprints, null: false
      t.integer :eligible_pages, null: false
      t.integer :thorough_passes, null: false
      t.string :backend, null: false
      t.datetime :created_at, null: false

      t.index [:website_id, :validation_run_id], unique: true, name: "unique_distillator_migration_validation"
      t.index [:website_id, :validated_at, :validation_run_id], name: "distillator_migration_baseline_history"
    end

    # The old badge was computed from live data and left no migration record.
    # Preserve the sites whose existing evidence can still establish that badge.
    Website.where(distillator_mode: "active").find_each do |website|
      Distillator::MigrationBaseline.capture!(website)
    end
  end

  def down
    drop_table :distillator_migration_baselines
  end
end
