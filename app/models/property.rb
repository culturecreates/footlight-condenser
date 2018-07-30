class Property < ApplicationRecord
  belongs_to :rdfs_class
  has_many :sources, dependent: :destroy
end
