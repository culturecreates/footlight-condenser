class Source < ApplicationRecord
  belongs_to :property
  belongs_to :website
  has_many :statements, dependent: :destroy
end
