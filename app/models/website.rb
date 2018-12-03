class Website < ApplicationRecord
  has_many :webpages, dependent: :destroy
  has_many :sources, dependent: :destroy

  validates :graph_name, presence: true, format: { with: /\Ahttp.*\..*\w\z/} #must start with http, contain a "." and not end with "/"
end
