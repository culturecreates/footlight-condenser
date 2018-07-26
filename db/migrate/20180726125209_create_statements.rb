class CreateStatements < ActiveRecord::Migration[5.1]
  def change
    create_table :statements do |t|
      t.string :cache
      t.string :status
      t.string :status_origin
      t.datetime :cache_refreshed
      t.datetime :cache_changed
      t.references :property, foreign_key: true
      t.references :webpage, foreign_key: true

      t.timestamps
    end
  end
end
