class AddSchedulingToWebsite < ActiveRecord::Migration[5.2]
  def change
    add_column :websites, :schedule_every_days, :integer
    add_column :websites, :last_refresh, :datetime
    add_column :websites, :schedule_time, :time
  end
end
