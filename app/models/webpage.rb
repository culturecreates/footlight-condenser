class Webpage < ApplicationRecord
  PUBLIC_SOURCE_URL_SQL = "(webpages.url LIKE 'http://%' OR webpages.url LIKE 'https://%')".freeze
  PUBLISHABLE_STATUSES = %w[ok updated].freeze

  belongs_to :rdfs_class
  belongs_to :website
  belongs_to :jsonld_output, optional: true
  has_many :statements, dependent: :destroy
  scope :public_source_urls, -> { where(PUBLIC_SOURCE_URL_SQL) }
  scope :internal_uris, -> { where.not(id: public_source_urls.select(:id)) }
  scope :active, -> { where("archive_date IS NULL OR archive_date > ?", Time.zone.now) }
  scope :publishable, -> { where(id: publishable_relation.select(:id)) }
  scope :not_publishable, -> { where.not(id: publishable.select(:id)) }
  scope :transition_candidates, -> { order(:archive_date, :id) }
  scope :event_pages, -> { joins(:rdfs_class).where(rdfs_classes: { name: "Event" }) }
  validates :url, uniqueness: { scope: :website_id }
  validates :rdf_uri, presence: true

  # for pagination
  self.per_page = 18

  after_initialize :init

  before_save :prevent_distant_archive_dates

  def init
    self.archive_date ||= Time.zone.now.next_year
  end

  def prevent_distant_archive_dates
    if self.archive_date < Time.zone.now - 10.years ||
       self.archive_date > Time.zone.now + 10.years
      self.archive_date = Time.zone.now.next_year
    end
  end

  def self.public_source_url_sql
    PUBLIC_SOURCE_URL_SQL
  end

  def self.publishable_relation
    title_statement_webpage_ids = publishable_statement_webpage_ids_for("Title")
    location_statement_webpage_ids = publishable_statement_webpage_ids_for("Location")
    dates_statement_webpage_ids = publishable_statement_webpage_ids_for("Dates")
      .where("LENGTH(COALESCE(statements.cache, '')) > 3")

    event_pages
      .where(id: title_statement_webpage_ids)
      .where(id: location_statement_webpage_ids)
      .where(id: dates_statement_webpage_ids)
  end

  def self.publishable_statement_webpage_ids_for(property_label)
    event_class_ids = RdfsClass.where(name: "Event").select(:id)

    Statement.joins(source: :property)
             .where(status: PUBLISHABLE_STATUSES)
             .where(sources: { selected: true })
             .where(properties: { label: property_label, rdfs_class_id: event_class_ids })
             .select(:webpage_id)
  end
end
