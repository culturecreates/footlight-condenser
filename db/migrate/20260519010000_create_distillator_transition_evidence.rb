class CreateDistillatorTransitionEvidence < ActiveRecord::Migration[8.0]
  def change
    create_table :distillator_transition_evidence do |t|
      t.references :website, null: false, foreign_key: true
      t.string :url, null: false
      t.string :cohort_key
      t.string :check_kind, null: false
      t.string :status, null: false
      t.integer :statement_delta
      t.boolean :statement_count_delta_acceptable
      t.boolean :export_diff_checked
      t.string :export_diff_status
      t.boolean :export_diff_accepted
      t.integer :rdf_added_count
      t.integer :rdf_removed_count
      t.string :wringer_uri_key
      t.string :distillator_uri_key
      t.integer :wringer_http_code
      t.integer :distillator_http_code
      t.string :primary_issue_key
      t.jsonb :details, default: {}, null: false
      t.datetime :checked_at, null: false

      t.timestamps
    end

    add_index :distillator_transition_evidence, :cohort_key
    add_index :distillator_transition_evidence, :check_kind
    add_index :distillator_transition_evidence, :status
    add_index :distillator_transition_evidence, :checked_at
    add_index :distillator_transition_evidence, [:website_id, :check_kind, :checked_at], name: "index_transition_evidence_on_site_kind_checked_at"
    add_index :distillator_transition_evidence, [:website_id, :url, :check_kind, :checked_at], name: "index_transition_evidence_on_site_url_kind_checked_at"
  end
end
