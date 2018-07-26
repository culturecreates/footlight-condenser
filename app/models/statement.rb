class Statement < ApplicationRecord
  belongs_to :property
  belongs_to :webpage

  validates :property, uniqueness: { scope: :webpage }
end
