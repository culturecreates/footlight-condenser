class Webpage < ApplicationRecord
  belongs_to :rdfs_class
  belongs_to :website
  has_many :statements, dependent: :destroy

  validates :url, uniqueness: { scope: :website_id }

  # for pagination
  self.per_page = 18

  after_initialize :init

  def init
    self.archive_date  ||=  Time.now.next_year          #will set the default value only if it's nil
  end

end
