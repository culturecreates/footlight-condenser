class CreateRdfsClasses < ActiveRecord::Migration[5.1]
  def change
    create_table :rdfs_classes do |t|
      t.string :name

      t.timestamps
    end
  end
end
