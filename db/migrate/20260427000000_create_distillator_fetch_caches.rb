class CreateDistillatorFetchCaches < ActiveRecord::Migration[8.0]
  def change
    create_table :distillator_fetch_caches do |t|
      t.string :uri_key, null: false
      t.string :normalized_url
      t.text :html
      t.text :body
      t.string :name
      t.jsonb :json_ld
      t.datetime :scrape_date
      t.datetime :successful_refresh
      t.integer :http_response_code
      t.jsonb :headers, null: false, default: {}
      t.jsonb :signals, null: false, default: {}
      t.jsonb :hints, null: false, default: []
      t.string :final_url
      t.jsonb :redirect_chain, null: false, default: []

      t.timestamps
    end

    add_index :distillator_fetch_caches, :uri_key, unique: true
  end
end
