class CreateProperties < ActiveRecord::Migration[5.1]
  def change
    create_table :properties do |t|
      t.string :label
      t.string :value_datatype
      t.string :uri
      t.references :rdfs_class, foreign_key: true

      t.timestamps
    end
  end
end
