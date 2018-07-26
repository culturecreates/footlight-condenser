class Statement < ApplicationRecord
  belongs_to :property
  belongs_to :webpage
end
