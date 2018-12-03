class AddGraphNameToWebsite < ActiveRecord::Migration[5.1]
  def change
    add_column :websites, :graph_name, :string, default: "http://artsdata.ca"
  end
end
