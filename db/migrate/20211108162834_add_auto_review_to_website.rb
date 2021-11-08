class AddAutoReviewToWebsite < ActiveRecord::Migration[5.2]
  def change
    add_column :websites, :auto_review, :boolean, default: false
  end
end
