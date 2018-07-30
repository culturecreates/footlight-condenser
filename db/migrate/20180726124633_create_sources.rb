class CreateSources < ActiveRecord::Migration[5.1]
  def change
    create_table :sources do |t|
      t.string :algorithm_value
      t.boolean :selected
      t.string :selected_by
      t.bigint :next_step
      t.string :language
      t.boolean :render_js
      t.references :property, foreign_key: true
      t.references :website, foreign_key: true

      t.timestamps
    end
  end
end
