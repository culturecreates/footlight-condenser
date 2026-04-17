class AddProvinceToWebsites < ActiveRecord::Migration[8.0]
  def change
    add_column :websites, :province, :string
  end
end
