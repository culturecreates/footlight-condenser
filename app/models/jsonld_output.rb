class JsonldOutput < ApplicationRecord
  has_many :webpage

  validates :frame, presence: true
end
