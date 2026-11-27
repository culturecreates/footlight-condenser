class TrackResourceListMonitoring < ActiveRecord::Migration[8.0]
  def change
    create_table :resource_list_monitoring_states do |t|
      t.references :webpage, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.references :website, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :scheduled_at
      t.datetime :verified_at
      t.datetime :probed_at
      t.datetime :completed_at
      t.string :contents_digest
      t.jsonb :listed_urls, default: [], null: false
      t.jsonb :absent_archived_urls, default: [], null: false
      t.jsonb :pending_probe_urls, default: [], null: false
      t.integer :reappearances, default: 0, null: false
      t.timestamps
    end

    change_column_null :monitoring_issues, :source_id, true
    add_column :monitoring_issues, :webpage_id, :bigint
    add_column :monitoring_issues, :evidence, :jsonb, default: {}, null: false
    add_index :monitoring_issues, [:kind, :webpage_id]
  end
end
