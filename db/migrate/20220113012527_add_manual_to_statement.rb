class AddManualToStatement < ActiveRecord::Migration[5.2]
  def change
    add_column :statements, :manual, :boolean, default: false
  end
end
