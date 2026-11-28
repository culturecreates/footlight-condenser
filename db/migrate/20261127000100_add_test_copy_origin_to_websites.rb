# frozen_string_literal: true

class AddTestCopyOriginToWebsites < ActiveRecord::Migration[8.0]
  def change
    add_reference :websites, :test_copy_of_website, foreign_key: { to_table: :websites }, index: true
    add_index :websites, "lower(seedurl)", unique: true, name: "index_websites_on_lower_seedurl_unique"
  end
end
