class CreatePredicates < ActiveRecord::Migration[5.1]
  def change
    create_table :predicates do |t|
      t.string :label
      t.string :language
      t.string :object_datatype
      t.string :uri

      t.timestamps
    end
  end
end
