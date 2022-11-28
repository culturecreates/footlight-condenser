class Webpage < ApplicationRecord
  belongs_to :rdfs_class
  belongs_to :website
  has_many :statements, dependent: :destroy

  validates :url, uniqueness: { scope: :website_id }
  validates :rdf_uri, presence: true

  # for pagination
  self.per_page = 18

  after_initialize :init

  before_save :prevent_distant_archive_dates

  def init
    self.archive_date ||= Time.now.next_year
  end

  def prevent_distant_archive_dates
    if self.archive_date < Time.now - 10.years ||
       self.archive_date > Time.now + 10.years
      self.archive_date = Time.now.next_year
    end
  end
end
