class AddWeeklyMonitoringPulse < ActiveRecord::Migration[8.0]
  def change
    add_column :monitoring_settings, :weekly_pulse_enabled, :boolean, default: true, null: false
    add_column :monitoring_settings, :last_pulse_week_on, :date
  end
end
