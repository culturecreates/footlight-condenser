class Website < ApplicationRecord
  has_many :webpages, dependent: :destroy
  has_many :sources, dependent: :destroy

  validates :graph_name,
            presence: true,
            format: { with: URI::DEFAULT_PARSER.make_regexp }

  validates :default_language, inclusion: { in: %w(en fr) }

  VALID_PROVINCES = %w[
    QC ON BC AB MB SK NS NB NL PE NT YT NU
  ].freeze

  validates :province, inclusion: { in: VALID_PROVINCES }, allow_nil: true
  validates :city, length: { maximum: 100 }, allow_nil: true

  before_validation :default_values, :normalize_province, :normalize_city

  def default_values
    self.default_language ||= 'en'
  end

  def normalize_province
    normalized = province.to_s.strip.upcase
    self.province = VALID_PROVINCES.include?(normalized) ? normalized : nil
  end

  def normalize_city
    self.city = city.to_s.strip.presence
  end
end