module Distillator
  class TransitionBatch < ApplicationRecord
    self.table_name = "distillator_transition_batches"
    CHECK_PROFILES = {
      "light" => { "sample_mode" => "default", "strictness" => "standard" }.freeze,
      "thorough" => { "sample_mode" => "all", "strictness" => "strict" }.freeze
    }.freeze
    DEFAULT_CHECK_PROFILE = "thorough".freeze
    has_many :site_transitions, class_name: "Distillator::SiteTransition", foreign_key: :batch_id, dependent: :destroy
    validates :request_key, presence: true, uniqueness: true
    validates :workflow_action, inclusion: { in: %w[validate audit verify] }
    validate do
      errors.add(:check_options, "must match Light or Thorough") unless CHECK_PROFILES.value?(check_options)
      errors.add(:check_options, "cannot change after submission") if persisted? && will_save_change_to_check_options?
      errors.add(:request_key, "cannot change after submission") if persisted? && will_save_change_to_request_key?
      errors.add(:workflow_action, "cannot change after submission") if persisted? && will_save_change_to_workflow_action?
      errors.add(:check_options, "must be Thorough for an audit") if audit? && check_profile != "thorough"
    end

    def self.request!(website_ids:, request_key:, selection_context: nil, check_profile: DEFAULT_CHECK_PROFILE, workflow_action: "validate", retry_of: nil)
      raise ArgumentError, "Select at least one event site" unless website_ids.is_a?(Array) && website_ids.any?
      raise ArgumentError, "Choose validation or an Active audit." unless workflow_action.in?(%w[validate audit])
      check_profile = "thorough" if workflow_action == "audit"
      options = CHECK_PROFILES.fetch(check_profile) { raise ArgumentError, "Choose Light or Thorough." }
      ids = website_ids.map { |value| Integer(value.to_s, 10) }.uniq.sort
      raise ArgumentError, "Invalid selection" if ids.any? { |id| id <= 0 } || request_key.to_s !~ /\A[\w-]{16,80}\z/
      if (existing = find_by(request_key: request_key))
        return reuse_request!(existing, ids, options, workflow_action)
      end
      created = false
      batch = transaction do
        websites = Website.where(id: ids).order(:id).lock.to_a
        if (same_request = find_by(request_key: request_key))
          next reuse_request!(same_request, ids, options, workflow_action)
        end
        unless websites.size == ids.size && EventSiteSelection.eligible_ids(websites).sort == ids
          raise ArgumentError, "Only event sites are eligible. Templates, tests and place/person sites are excluded."
        end
        if retry_of && (workflow_action != "validate" || (ids - retry_of.retry_website_ids(websites)).any?)
          raise ArgumentError, "Retry includes only currently non-Active event sites from the completed group."
        end
        if workflow_action == "audit" && websites.any? { |website| website.distillator_mode != "active" }
          raise ArgumentError, "Select only Active event sites for an audit."
        end
        # Website locks also serialize admission against standalone requests and
        # late result publication. Workflow-owned runs must recover via their owner.
        owned_ids = SiteTransition.active.where(website_id: ids).pluck(:website_id)
        TransitionRun.active.where(website_id: ids - owned_ids).where(requested_at: ..(Time.current - TransitionRun::LEASE)).each do |run|
          run.fail!("Check expired. Replaced by a validation workflow request.")
        end
        busy = owned_ids | TransitionRun.active.where(website_id: ids).pluck(:website_id)
        if busy.any?
          names = websites.select { |website| busy.include?(website.id) }.first(5).map { |website| website.name.presence || website.seedurl }.join(", ")
          raise ArgumentError, "Already running or queued: #{names}. Follow the existing check before starting another workflow."
        end
        estimates = TransitionTimeEstimate.for_sites(websites, check_options: TransitionCheckOptions.new(options),
          shadow_first: workflow_action == "validate" && check_profile == "thorough")
        events = RolloutEvent.where(website_id: ids).group(:website_id).maximum(:id)
        create!(request_key: request_key, selection_context: selection_context.to_s.first(300), check_options: options,
          workflow_action: workflow_action).tap do |record|
          created = true
          rows = websites.each_with_index.map do |website, index|
            { batch_id: record.id, website_id: website.id, website_name: website.name.presence || website.seedurl.presence || "Website ##{website.id}",
              seedurl: website.seedurl, position: index, initial_mode: website.distillator_mode, expected_mode: website.distillator_mode,
              expected_event_id: events[website.id], estimated_seconds: estimates[website.id], created_at: Time.current, updated_at: Time.current }
          end
          SiteTransition.insert_all!(rows)
        end
      end
      batch.enqueue_next! if created
      batch
    end

    def self.reuse_request!(batch, ids, options, workflow_action)
      raise ArgumentError, "This request belongs to a different selection" unless batch.site_transitions.order(:website_id).pluck(:website_id) == ids
      raise ArgumentError, "This request belongs to a different workflow action" unless batch.workflow_action == workflow_action
      raise ArgumentError, "This request belongs to a different check profile" unless batch.check_options == options

      batch
    end
    private_class_method :reuse_request!

    def check_profile
      CHECK_PROFILES.key(check_options)
    end

    def audit?
      workflow_action == "audit"
    end

    def retry_website_ids(websites = Website.where(id: site_transitions.select(:website_id)))
      return [] unless site_transitions.exists? && !site_transitions.active.exists?

      group_ids = site_transitions.pluck(:website_id)
      candidates = websites.reject { |site| site.distillator_mode == "active" || !group_ids.include?(site.id) }
      EventSiteSelection.eligible_ids(candidates)
    end

    def thorough_revalidation?
      workflow_action == "validate" && check_profile == "thorough"
    end

    def enqueue_next!
      with_lock do
        return if stopped_at || site_transitions.where(status: "running").exists?
        item = site_transitions.where(status: "queued").order(:position).first
        dispatch!(SiteTransitionJob, item.id, phase: "queued") if item
      end
    rescue StandardError => error
      # Keep the durable queued selection available for the periodic reconciler.
      Rails.logger.warn(event: "distillator.batch.enqueue_failed", id: id, error_class: error.class.name)
      false
    end

    def reconcile!
      with_lock do
        return if last_reconciled_at && last_reconciled_at > 1.minute.ago
        item = site_transitions.where(status: "running").order(:position).first
        if item
          if item.deadline_at && item.deadline_at <= Time.current
            dispatch!(SiteTransitionWatchdogJob, item.id)
          elsif item.cancel_requested_at? || item.phase_started_at.nil?
            dispatch!(SiteTransitionJob, item.id, phase: item.phase)
          elsif (run = item.current_run) && (run.status == "queued" || (run.resumable? && run.status == "completed"))
            dispatch!(SiteTransitionJob, item.id, phase: item.phase)
          end
        elsif !stopped_at
          item = site_transitions.where(status: "queued").order(:position).first
          dispatch!(SiteTransitionJob, item.id, phase: "queued") if item
        end
        update_column(:last_reconciled_at, Time.current)
      end
    end

    def stop_remaining!(reason: "Stopped by the operator before this site started")
      with_lock do
        update!(stopped_at: Time.current)
        site_transitions.where(status: "queued").update_all(status: "cancelled", phase: "finished", reason: reason, completed_at: Time.current)
      end
    end

    private

    def dispatch!(job_class, *args, **kwargs)
      job = job_class.perform_later(*args, **kwargs)
      raise "Job enqueue declined" unless job
      job
    end
  end
end
