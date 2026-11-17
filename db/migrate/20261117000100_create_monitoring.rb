class CreateMonitoring < ActiveRecord::Migration[8.0]
  def change
    create_table :monitoring_settings do |t|
      t.string :mailbox
      t.date :last_digest_on
      t.timestamps
    end
    add_check_constraint :monitoring_settings, "id = 1", name: "monitoring_settings_singleton"

    create_table :monitoring_issues do |t|
      t.string :fingerprint, null: false
      t.string :seedurl, null: false
      t.string :website_name
      t.text :url
      t.bigint :source_id, null: false
      t.bigint :statement_id
      t.string :property_name
      t.text :message, null: false
      t.integer :occurrences, null: false, default: 1
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :monitoring_issues, :fingerprint, unique: true
    add_index :monitoring_issues, [:seedurl, :resolved_at]
    add_index :monitoring_issues, :last_seen_at
  end
end
