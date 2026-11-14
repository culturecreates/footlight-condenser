module Distillator
  class TransitionExclusion < ApplicationRecord
    self.table_name = "distillator_transition_exclusions"

    belongs_to :website
    belongs_to :source_run, class_name: "Distillator::TransitionRun"
    scope :active, -> { where(revoked_at: nil) }
    validates :url, format: { with: /\Ahttps?:\/\// }, presence: true
    validates :reason, presence: true, length: { maximum: 2000 }
    validates :revocation_reason, presence: true, length: { maximum: 2000 }, if: -> { revoked_at.present? }
    validate :preserve_review_record
    validate :matching_website
    validate :verified_source_evidence, on: :create

    def snapshot
      { id: id, url: url, reason: reason, reviewed_at: created_at.iso8601(6), source_run_id: source_run_id }
    end

    private

    def preserve_review_record
      return unless persisted?

      if (changed - %w[revoked_at revocation_reason updated_at]).any? || revoked_at_in_database.present?
        errors.add(:base, "Recorded reviews cannot be edited; restore the URL and record a new review instead")
      end
    end

    def matching_website
      errors.add(:source_run, "must belong to this website") if source_run && source_run.website_id != website_id
    end

    def verified_source_evidence
      row = Distillator::TransitionExclusionReview.eligible_rows(source_run).find { |entry| entry[:url] == url }
      unless row && row.as_json == recorded_evidence.as_json
        errors.add(:recorded_evidence, "must match fresh source 404/410 results from both backends")
      end
    end
  end
end
