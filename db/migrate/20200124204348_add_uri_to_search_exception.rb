class AddUriToSearchException < ActiveRecord::Migration[5.1]
  def change
    add_column :search_exceptions, :uri, :string
  end
end
