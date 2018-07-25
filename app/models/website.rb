class Website < ApplicationRecord
  has_many :webpages, dependent: :destroy
end
