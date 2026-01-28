class AddArchiveDateToWebpage < ActiveRecord::Migration[5.1]
  def change
    add_column :webpages, :archive_date, :datetime, default: Time.zone.now.next_year
  end
end
