class ObjectClass < ApplicationRecord
  has_many :webpages, dependent: :destroy
end
