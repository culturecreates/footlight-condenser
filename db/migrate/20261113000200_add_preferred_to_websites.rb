class AddPreferredToWebsites < ActiveRecord::Migration[8.0]
  def change
    add_column :websites, :preferred, :boolean, default: false, null: false
  end
end
