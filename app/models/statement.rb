class Statement < ApplicationRecord
  belongs_to :status
  belongs_to :predicate
  belongs_to :webpage
end
