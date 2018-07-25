class CreateWebsites < ActiveRecord::Migration[5.1]
  def change
    create_table :websites do |t|
      t.string :name
      t.string :seedurl

      t.timestamps
    end
  end
end
