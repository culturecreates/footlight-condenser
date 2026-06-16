class Website < ApplicationRecord
  # Rollout modes are website-level production states.
  # They intentionally do not expose Distillator's internal execution naming.
  DISTILLATOR_MODES = %w[legacy shadow active].freeze

  has_many :webpages, dependent: :destroy
  has_many :sources, dependent: :destroy
  has_many :transition_evidences,
           class_name: "Distillator::TransitionEvidence",
           dependent: :destroy,
           inverse_of: :website
  has_many :rollout_events,
           class_name: "Distillator::RolloutEvent",
           dependent: :destroy,
           inverse_of: :website

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
    distillator_mode.to_sym
  end

  def distillator_cohort_memberships
    Distillator::Cohorts::Matcher.memberships_for(self)
  end

  def distillator_primary_cohort
    distillator_cohort_memberships.first
  end

  def distillator_primary_cohort_key
    distillator_primary_cohort&.dig(:key)
  end

  def distillator_primary_cohort_label
    distillator_primary_cohort&.dig(:label)
  end

  def lavitrine_pipeline?
    Distillator::Cohorts::Matcher.match?(self, Distillator::Cohorts::LavitrinePipeline.key)
  end

  def latest_transition_evidence(check_kind = nil)
    Distillator::TransitionEvidence.latest_for_website(self, check_kind)
  end

  def latest_transition_evidences_by_kind
    @latest_transition_evidences_by_kind ||= transition_evidences.latest_first.group_by(&:check_kind).transform_values(&:first)
  end

  def latest_transition_evidence_checked_at
    transition_evidences.where(check_kind: Distillator::TransitionEvidence::REPORT_CHECK_KINDS).maximum(:checked_at)
  end

  def pending_transition_batch_check?
    return false if transition_check_requested_at.blank?

    latest_transition_evidence_checked_at.blank? || latest_transition_evidence_checked_at <= transition_check_requested_at
  end

  def request_transition_batch_check!(requested_at: Time.current)
    update!(transition_check_requested_at: requested_at)
  end

  private

  def auto_set_monitorable
    return if seedurl.blank?

    return unless seedurl.match?(/(^[0-9]|test|rlist|footlight)/i)

    self.monitorable = false
  end
end
