class Website < ApplicationRecord
  has_many :webpages, dependent: :destroy
  has_many :sources, dependent: :destroy

  validates :graph_name, presence: true, format: { with: /\Ahttp.*\..*\w\z/ } # must start with http, contain a "." and not end with "/"
  validates :default_language, inclusion: { in: %w(en fr) }

  before_save :default_values
  before_validation :auto_set_monitorable

  def default_values
    self.default_language ||= 'en'
  end

  private

  def auto_set_monitorable
    return if seedurl.blank?

    return unless seedurl.match?(/(^[0-9]|test|rlist|footlight)/i)

    self.monitorable = false
    
  end
end