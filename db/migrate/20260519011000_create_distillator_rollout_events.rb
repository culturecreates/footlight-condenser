class CreateDistillatorRolloutEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :distillator_rollout_events do |t|
      t.references :website, null: false, foreign_key: true
      t.string :from_mode
      t.string :to_mode, null: false
      t.string :actor
      t.string :reason
      t.jsonb :readiness_snapshot, default: {}, null: false

      t.timestamps
    end

    add_index :distillator_rollout_events, :to_mode
    add_index :distillator_rollout_events, [:website_id, :created_at]
  end
end
