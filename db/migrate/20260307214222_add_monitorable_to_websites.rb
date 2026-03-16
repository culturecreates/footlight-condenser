class AddMonitorableToWebsites < ActiveRecord::Migration[8.0]
  def change
    add_column :websites, :monitorable, :boolean
  end
end
