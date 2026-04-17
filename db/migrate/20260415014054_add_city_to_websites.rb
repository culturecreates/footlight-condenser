class AddCityToWebsites < ActiveRecord::Migration[8.0]
  def change
    add_column :websites, :city, :string
  end
end
