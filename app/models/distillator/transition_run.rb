module Distillator
  class TransitionRun < ApplicationRecord
    self.table_name = "distillator_transition_runs"
    LEASE = 1.hour
    STATUSES = %w[queued running completed failed].freeze
    class ConfigurationChanged < StandardError; end
    class OptionsConflict < StandardError; end
    class WorkflowBusy < ArgumentError; end
    Request = Struct.new(:run, :created?, keyword_init: true)

    belongs_to :website
    has_many :transition_evidences, class_name: "Distillator::TransitionEvidence", dependent: :destroy
    validates :status, inclusion: { in: STATUSES }
    validates :configuration_digest, :requested_at, presence: true
    validate :valid_check_options
    scope :active, -> { where(status: %w[queued running]) }
    scope :completed, -> { where(status: "completed") }

    def self.request!(website:, options: {}, workflow_item: nil)
      requested_options = Distillator::TransitionCheckOptions.coerce(options)
      website.with_lock do
        owner = SiteTransition.active.find_by(website_id: website.id)
        if owner && owner.id != workflow_item&.id
          raise WorkflowBusy, "This website belongs to validation workflow ##{owner.id}. Follow that workflow before starting another check."
        end
        current = active.find_by(website_id: website.id)
        if current && current.requested_at > Time.current - LEASE
          unless current.options.to_h == requested_options.to_h
            raise OptionsConflict, "Run ##{current.id} is already #{current.status} with different check options. Wait for it to finish before requesting another scope."
          end
          next Request.new(run: current, created?: false)
        end
        current&.update!(status: "failed", completed_at: Time.current, error_message: "Check expired. A new run was requested.")
        run = create!(website: website, requested_at: Time.current,
          configuration_digest: Distillator::TransitionFingerprint.call(website), check_options: requested_options.to_h)
        website.update_column(:transition_check_requested_at, run.requested_at)
        Request.new(run: run, created?: true)
      end
    end

    def options
      Distillator::TransitionCheckOptions.new(check_options)
    end

    def record_progress!(phase, completed: nil, total: nil)
      self.class.where(id: id, status: "running").update_all(progress: {
        phase: phase, completed: completed, total: total, updated_at: Time.current.iso8601(6)
      }.compact)
    end

    def execute
      claimed = website.with_lock do
        with_lock do
          next false unless status == "queued"
          raise ConfigurationChanged, "Check expired. Run a new check." if requested_at <= Time.current - LEASE
          update!(status: "running", started_at: Time.current)
          true
        end
      end
      return unless claimed

      result = yield self
      website.with_lock do
        with_lock do
          unless status == "running" && requested_at > Time.current - LEASE &&
              configuration_digest == Distillator::TransitionFingerprint.call(website)
            raise ConfigurationChanged, "Check expired or source configuration changed. Run a new check."
          end
          kinds = transition_evidences.distinct.pluck(:check_kind)
          unless (Distillator::TransitionEvidence::REPORT_CHECK_KINDS - kinds).empty?
            raise ConfigurationChanged, "Check did not finish all required phases. Run a new check."
          end
          update!(status: "completed", completed_at: Time.current)
        end
      end
      result
    rescue StandardError => error
      fail!(error.is_a?(ConfigurationChanged) ? error.message : "Transition check failed (#{error.class.name}). Check logs and retry.")
      raise
    end

    def fail!(message)
      self.class.where(id: id, status: %w[queued running]).update_all(
        status: "failed", completed_at: Time.current, error_message: message, updated_at: Time.current)
      reload
    end

    private

    def valid_check_options
      options
      if persisted? && will_save_change_to_check_options?
        errors.add(:check_options, "cannot change after the check is requested")
      end
    rescue ArgumentError => error
      errors.add(:check_options, error.message)
    end
  end
end
