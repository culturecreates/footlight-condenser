class CreateSources < ActiveRecord::Migration[5.1]
  def change
    create_table :sources do |t|
      t.string :algorithm_value
      t.boolean :selected
      t.string :selected_by
      t.boolean :render_js
      t.references :predicate, foreign_key: true
      t.bigint :next_source_id
      t.references :website, foreign_key: true

      t.timestamps
    end
  end
end
