class AddIssueFieldsToDistillatorFetchCaches < ActiveRecord::Migration[8.0]
  def change
    change_table :distillator_fetch_caches, bulk: true do |t|
      t.string :primary_issue_key
      t.string :primary_issue_error_code
      t.string :primary_issue_label
      t.string :primary_issue_severity
      t.string :primary_issue_category
      t.jsonb :issue_keys, null: false, default: []
      t.jsonb :issue_hints, null: false, default: []
      t.boolean :delete_candidate, null: false, default: false
    end

    add_index :distillator_fetch_caches, :primary_issue_key
    add_index :distillator_fetch_caches, :primary_issue_severity
    add_index :distillator_fetch_caches, :primary_issue_category
    add_index :distillator_fetch_caches, :delete_candidate
    add_index :distillator_fetch_caches, :issue_keys, using: :gin
    add_index :distillator_fetch_caches, :issue_hints, using: :gin
  end
end
