class AddAutoReviewToSource < ActiveRecord::Migration[5.2]
  def change
    add_column :sources, :auto_review, :boolean, default: false
    remove_column :websites, :auto_review
  end
end
