class Predicate < ApplicationRecord
  has_many :sources
  has_many :statements
end
