class AddHealthFieldsToDistillatorFetchCaches < ActiveRecord::Migration[8.0]
  def change
    change_table :distillator_fetch_caches, bulk: true do |t|
      t.string :health_status
      t.string :health_severity
      t.jsonb :health_reasons, null: false, default: []
      t.integer :html_bytes, null: false, default: 0
      t.integer :body_bytes, null: false, default: 0
      t.boolean :redirected, null: false, default: false
      t.string :network_status
      t.string :content_type
      t.jsonb :hint_keys, null: false, default: []
    end

    add_index :distillator_fetch_caches, :health_status
    add_index :distillator_fetch_caches, :health_severity
    add_index :distillator_fetch_caches, :http_response_code
    add_index :distillator_fetch_caches, :network_status
    add_index :distillator_fetch_caches, :content_type
    add_index :distillator_fetch_caches, :redirected
    add_index :distillator_fetch_caches, :successful_refresh
    add_index :distillator_fetch_caches, :scrape_date
    add_index :distillator_fetch_caches, :updated_at
    add_index :distillator_fetch_caches, :signals, using: :gin
    add_index :distillator_fetch_caches, :hints, using: :gin
    add_index :distillator_fetch_caches, :redirect_chain, using: :gin
  end
end
