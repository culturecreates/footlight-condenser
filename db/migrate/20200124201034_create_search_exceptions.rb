class CreateSearchExceptions < ActiveRecord::Migration[5.1]
  def change
    create_table :search_exceptions do |t|
      t.string :name
      t.references :rdfs_class, foreign_key: true

      t.timestamps
    end
  end
end
