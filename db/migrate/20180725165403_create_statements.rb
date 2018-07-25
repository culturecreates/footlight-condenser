class CreateStatements < ActiveRecord::Migration[5.1]
  def change
    create_table :statements do |t|
      t.references :status, foreign_key: true
      t.references :predicate, foreign_key: true
      t.references :webpage, foreign_key: true
      t.string :cache
      t.string :status_origin
      t.datetime :cache_refreshed
      t.datetime :cache_changed

      t.timestamps
    end
  end
end
