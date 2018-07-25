class Source < ApplicationRecord
  belongs_to :source
  belongs_to :website
  belongs_to :predicate
end
