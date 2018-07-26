class RdfsClass < ApplicationRecord
  has_many :properties, dependent: :destroy
  has_many :webpages, dependent: :destroy
end
