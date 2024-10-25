class AddJsonldOutputToWebpages < ActiveRecord::Migration[5.2]
  def change
    add_reference :webpages, :jsonld_output, foreign_key: true
  end
end
