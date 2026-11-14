module Distillator
  class TransitionBatch < ApplicationRecord
    self.table_name = "distillator_transition_batches"
    has_many :site_transitions, class_name: "Distillator::SiteTransition", foreign_key: :batch_id, dependent: :destroy
    validates :request_key, presence: true, uniqueness: true
    validate do
      errors.add(:check_options, "must remain All pages and Strict") unless check_options == { "sample_mode" => "all", "strictness" => "strict" }
      errors.add(:request_key, "cannot change after submission") if persisted? && will_save_change_to_request_key?
    end

    def self.request!(website_ids:, request_key:, selection_context: nil)
      raise ArgumentError, "Select at least one event site" unless website_ids.is_a?(Array) && website_ids.any?
      ids = website_ids.map { |value| Integer(value.to_s, 10) }.uniq.sort
      raise ArgumentError, "Invalid selection" if ids.any? { |id| id <= 0 } || request_key.to_s !~ /\A[\w-]{16,80}\z/
      if (existing = find_by(request_key: request_key))
        raise ArgumentError, "This request belongs to a different selection" unless existing.site_transitions.order(:website_id).pluck(:website_id) == ids
        return existing
      end
      created = false
      batch = transaction do
        websites = Website.where(id: ids).order(:id).lock.to_a
        if (same_request = find_by(request_key: request_key))
          raise ArgumentError, "This request belongs to a different selection" unless same_request.site_transitions.order(:website_id).pluck(:website_id) == ids
          next same_request
        end
        unless websites.size == ids.size && EventSiteSelection.eligible_ids(websites).sort == ids
          raise ArgumentError, "Only event sites are eligible. Templates, tests and place/person sites are excluded."
        end
        busy = SiteTransition.active.where(website_id: ids).pluck(:website_id) | TransitionRun.active.where(website_id: ids).pluck(:website_id)
        if busy.any?
          names = websites.select { |website| busy.include?(website.id) }.first(5).map { |website| website.name.presence || website.seedurl }.join(", ")
          raise ArgumentError, "Already running or queued: #{names}. Follow the existing check before starting another workflow."
        end
        estimates = TransitionTimeEstimate.for_sites(websites)
        events = RolloutEvent.where(website_id: ids).group(:website_id).maximum(:id)
        create!(request_key: request_key, selection_context: selection_context.to_s.first(300)).tap do |record|
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

    def enqueue_next!
      return if stopped_at || site_transitions.where(status: "running").exists?
      item = site_transitions.where(status: "queued").order(:position).first
      return unless item
      job = SiteTransitionJob.perform_later(item.id, phase: "queued")
      raise "Job enqueue declined" unless job
    rescue StandardError
      stop_remaining!(reason: "Unable to queue the workflow. Check the worker connection, then start a new selection.")
    end

    def stop_remaining!(reason: "Stopped by the operator before this site started")
      update!(stopped_at: Time.current)
      site_transitions.where(status: "queued").update_all(status: "cancelled", phase: "finished", reason: reason, completed_at: Time.current)
    end
  end
end
