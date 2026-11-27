module Distillator
  class TransitionEvidenceRecorder
    def self.call(...)
      new(...).call
    end

    def initialize(website:, url:, check_kind:, status:, checked_at: Time.current, cohort_key: nil, details: {}, **attributes)
      @website = website
      @url = url
      @check_kind = check_kind
      @status = status
      @checked_at = checked_at
      @cohort_key = cohort_key
      @details = details
      @attributes = attributes
    end

    def call
      run = attributes[:transition_run]
      if run
        return website.with_lock do
          run.with_lock do
            raise "Cannot append evidence to an inactive transition run" unless run.status == "running"
            create_record
          end
        end
      end
      create_record
    end

    private

    def create_record
      record = Distillator::TransitionEvidence.new
      record.assign_attributes(payload)
      record.save!
      record
    end

    attr_reader :website, :url, :check_kind, :status, :checked_at, :cohort_key, :details, :attributes

    def payload
      {
        website: website,
        url: normalized_url,
        cohort_key: cohort_key.presence || inferred_cohort_key,
        check_kind: check_kind.to_s,
        status: status.to_s,
        checked_at: checked_at,
        details: details.to_h
      }.merge(attributes.compact)
    end

    def normalized_url
      Distillator::WringerUrlKey.call(url).normalized_url
    rescue StandardError
      url.to_s
    end

    def inferred_cohort_key
      return unless website.respond_to?(:distillator_primary_cohort_key)

      website.distillator_primary_cohort_key
    end
  end
end
