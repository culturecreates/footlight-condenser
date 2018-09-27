class Webpage < ApplicationRecord
  belongs_to :rdfs_class
  belongs_to :website
  has_many :statements, dependent: :destroy

  validates :url, uniqueness: { scope: :website_id }
end
