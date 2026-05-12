class Website < ApplicationRecord
  # Rollout modes are website-level production states.
  # They intentionally do not expose Distillator's internal execution naming.
  DISTILLATOR_MODES = %w[legacy shadow active].freeze

  has_many :webpages, dependent: :destroy
  has_many :sources, dependent: :destroy

  validates :graph_name, presence: true, format: { with: /\Ahttp.*\..*\w\z/ } # must start with http, contain a "." and not end with "/"
  validates :default_language, inclusion: { in: %w(en fr) }
  validates :distillator_mode, inclusion: { in: DISTILLATOR_MODES }

  before_save :default_values
  before_validation :auto_set_monitorable

  def default_values
    self.default_language ||= 'en'
    self.distillator_mode ||= "legacy"
  end

  def distillator_fetch_mode
    # "active" rollout means the Distillator internal fetch path is the active execution path.
    return :internal if distillator_mode == "active"

    distillator_mode.to_sym
  end

  private

  def auto_set_monitorable
    return if seedurl.blank?

    return unless seedurl.match?(/(^[0-9]|test|rlist|footlight)/i)

    self.monitorable = false
  end
end
