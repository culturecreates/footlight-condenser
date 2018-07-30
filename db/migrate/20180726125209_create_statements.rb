class CreateStatements < ActiveRecord::Migration[5.1]
  def change
    create_table :statements do |t|
      t.string :cache
      t.string :status
      t.string :status_origin
      t.datetime :cache_refreshed
      t.datetime :cache_changed
      t.references :source, foreign_key: true
      t.references :webpage, foreign_key: true

      t.timestamps
    end

    add_index :statements, [:source_id, :webpage_id], unique: :true
  end
end
