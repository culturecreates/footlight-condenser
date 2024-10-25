class CreateJsonldOutputs < ActiveRecord::Migration[5.2]
  def change
    create_table :jsonld_outputs do |t|
      t.string :name
      t.references :webpage, foreign_key: true

      t.timestamps
    end
  end
end
