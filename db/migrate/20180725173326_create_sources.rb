class CreateSources < ActiveRecord::Migration[5.1]
  def change
    create_table :sources do |t|
      t.string :algorithm_value
      t.boolean :selected
      t.string :selected_by
      t.references :source, foreign_key: true
      t.references :website, foreign_key: true
      t.references :predicate, foreign_key: true
      t.boolean :render_js

      t.timestamps
    end
  end
end
