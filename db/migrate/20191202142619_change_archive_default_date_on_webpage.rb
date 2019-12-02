class ChangeArchiveDefaultDateOnWebpage < ActiveRecord::Migration[5.1]
  def change
    change_column_default(:webpages, :archive_date, nil)
  end
end
