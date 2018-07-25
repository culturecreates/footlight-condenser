class Website < ApplicationRecord
  has_many :webpages, dependent: :destroy
  has_many :sources, dependent: :destroy
end
