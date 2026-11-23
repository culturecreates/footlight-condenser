module Distillator
  class TransitionRun < ApplicationRecord
    self.table_name = "distillator_transition_runs"
    LEASE = 1.hour
    MAX_BATCH_ATTEMPTS = 3
    CONTINUE = :continue_transition
    CANCELLED_MESSAGE = "Cancelled by the operator".freeze
    STATUSES = %w[queued running completed failed].freeze
    class ConfigurationChanged < StandardError; end
    class Cancelled < StandardError; end
    class OptionsConflict < StandardError; end
    class WorkflowBusy < ArgumentError; end
    Request = Struct.new(:run, :created?, keyword_init: true)

    belongs_to :website
    has_many :transition_evidences, class_name: "Distillator::TransitionEvidence", dependent: :destroy
    has_many :transition_checkpoints, class_name: "Distillator::TransitionCheckpoint", foreign_key: :transition_run_id, dependent: :delete_all
    validates :status, inclusion: { in: STATUSES }
    validates :configuration_digest, :requested_at, presence: true
    validate :valid_check_options
    scope :active, -> { where(status: %w[queued running]) }
    scope :completed, -> { where(status: "completed") }
    scope :guarded_running, -> { where(status: "running").where("progress ->> 'execution_lock' = 'true'") }

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
      update = {
        phase: phase, completed: completed, total: total, updated_at: Time.current.iso8601(6)
      }.compact
      self.class.where(id: id, status: "running").update_all([
        "progress = (progress - ARRAY['phase', 'completed', 'total', 'updated_at']) || CAST(? AS jsonb)", update.to_json
      ])
    end

    def execute(resumable: false, cancellation_check: nil, &block)
      with_execution_lock { execute_claimed(resumable, cancellation_check, &block) }
    end

    def resumable?
      progress["resumable"] == true
    end

    def save_checkpoint!(offset:, page_count:, payload:)
      with_lock do
        raise ConfigurationChanged, "Check stopped before checkpointing." unless status == "running"
        transition_checkpoints.create!(offset: offset, page_count: page_count, payload: payload)
        update!(progress: progress.merge("batch_attempts" => 0))
      end
    end

    def recover_interrupted!
      with_execution_lock do
        reload
        yield if status == "running" && progress["execution_lock"] == true
      end
    end

    def fail!(message)
      self.class.where(id: id, status: %w[queued running]).update_all(
        status: "failed", completed_at: Time.current, error_message: message, updated_at: Time.current)
      reload
    end

    private

    # A PostgreSQL session lock disappears on process death. The marker is set
    # only after the lock is acquired, so legacy executions keep their lease.
    def with_execution_lock
      self.class.with_connection do |connection|
        key = "hashtextextended(#{connection.quote("distillator.transition_run:#{id}")}, 0)"
        acquired = self.class.uncached { connection.select_value("SELECT pg_try_advisory_lock(#{key})") }
        next unless acquired

        begin
          yield
        ensure
          self.class.uncached { connection.select_value("SELECT pg_advisory_unlock(#{key})") }
        end
      end
    end

    def execute_claimed(resumable, cancellation_check)
      claimed = website.with_lock do
        with_lock do
          next false unless status == "queued" || (status == "running" && resumable && resumable?)
          cancellation_check&.call
          raise ConfigurationChanged, "Check expired. Run a new check." if requested_at <= Time.current - LEASE
          if resumable
            unless configuration_digest == Distillator::TransitionFingerprint.call(website)
              raise ConfigurationChanged, "Check configuration changed. Run a new check."
            end
            attempts = progress.fetch("batch_attempts", 0)
            if attempts >= MAX_BATCH_ATTEMPTS
              raise ConfigurationChanged, "The verification batch was interrupted repeatedly. Coverage is incomplete."
            end
            update!(status: "running", started_at: started_at || Time.current,
              progress: progress.merge("execution_lock" => true, "resumable" => true, "batch_attempts" => attempts + 1))
          else
            update!(status: "running", started_at: Time.current, progress: { execution_lock: true })
          end
          true
        end
      end
      return unless claimed

      result = yield self
      cancellation_check&.call
      return result if resumable && result == CONTINUE
      website.with_lock do
        with_lock do
          cancellation_check&.call
          unless status == "running" && requested_at > Time.current - LEASE &&
              configuration_digest == Distillator::TransitionFingerprint.call(website)
            raise ConfigurationChanged, "Check expired or source configuration changed. Run a new check."
          end
          kinds = transition_evidences.distinct.pluck(:check_kind)
          unless (Distillator::TransitionEvidence::REPORT_CHECK_KINDS - kinds).empty?
            raise ConfigurationChanged, "Check did not finish all required phases. Run a new check."
          end
          update!(status: "completed", completed_at: Time.current)
          transition_checkpoints.delete_all if resumable
        end
      end
      result
    rescue Cancelled => error
      fail!(error.message)
      transition_checkpoints.delete_all
      raise
    rescue StandardError => error
      message = if error.is_a?(ConfigurationChanged) || error.is_a?(TransitionMemory::LimitExceeded)
        error.message
      else
        "Transition check failed (#{error.class.name}). Check logs and retry."
      end
      fail!(message)
      raise
    end

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
