class Webpage < ApplicationRecord
  belongs_to :rdfs_class
  belongs_to :website
  has_many :statements, dependent: :destroy
end
