class Webpage < ApplicationRecord
  belongs_to :website
  belongs_to :object_class
  has_many :statements, dependent: :destroy
end
