class Statement < ApplicationRecord
  belongs_to :source
  belongs_to :webpage

  validates :source, uniqueness: { scope: :webpage }
end
