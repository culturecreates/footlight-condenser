module Distillator
  class RolloutTransition
    Result = Struct.new(:success?, :website, :from_mode, :to_mode, :warnings, :blockers, :errors, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(website:, to_mode:, actor: nil, reason: nil, force: false, attributes: {})
      @website = website
      @raw_to_mode = to_mode
      @to_mode = normalize_mode(to_mode)
      @actor = actor
      @reason = reason
      @force = force
      @attributes = attributes.to_h.symbolize_keys.except(:distillator_mode)
    end

    def call
      website.assign_attributes(attributes)
      return failure(["Distillator mode is not included in the list"]) unless valid_target_mode?

      if blocked_transition_errors.any?
        blocked_transition_errors.each { |message| website.errors.add(:distillator_mode, message) }
        return failure(blocked_transition_errors)
      end

      warnings = transition_warnings
      from_mode = current_mode

      website.distillator_mode = to_mode
      if website.save
        Distillator::RolloutEventRecorder.call(
          website: website,
          from_mode: from_mode,
          to_mode: to_mode,
          actor: actor,
          reason: reason,
          readiness_snapshot: readiness_snapshot(warnings)
        )
        return Result.new(success?: true, website: website, from_mode: from_mode, to_mode: to_mode, warnings: warnings, blockers: [], errors: [])
      end

      failure(website.errors.full_messages)
    end

    private

    attr_reader :website, :to_mode, :actor, :reason, :force, :attributes, :raw_to_mode

    def current_mode
      website.distillator_mode.presence || "legacy"
    end

    def valid_target_mode?
      Website::DISTILLATOR_MODES.include?(to_mode)
    end

    def blocked_transition_errors
      @blocked_transition_errors ||= begin
        return [] if current_mode == to_mode
        return [] if current_mode == "legacy" && to_mode == "shadow"
        return [] if current_mode == "shadow" && to_mode == "legacy"
        return [] if current_mode == "active" && to_mode.in?(%w[legacy shadow])
        return legacy_to_active_errors if current_mode == "legacy" && to_mode == "active"
        return shadow_to_active_errors if current_mode == "shadow" && to_mode == "active"

        ["Unsupported rollout transition"]
      end
    end

    def legacy_to_active_errors
      return [] if force && !Rails.env.production? && !Rails.env.test?

      ["Direct legacy to active promotion is blocked"]
    end

    def shadow_to_active_errors
      return [] if transition_status.status == :ready

      return transition_status.blockers if transition_status.blockers.any?
      return transition_status.warnings.map { |message| activation_error_message(message) } if transition_status.warnings.any?

      ["Cannot activate yet: checks are not complete."]
    end

    def transition_warnings
      []
    end

    def transition_status
      @transition_status ||= Distillator::TransitionStatus.call(
        website: website,
        cache: Distillator::ShadowReportQuery.latest_cache_for_website(website),
        evidence_by_kind: website.latest_transition_evidences_by_kind
      )
    end

    def readiness_snapshot(warnings)
      {
        blockers: transition_status.blockers,
        warnings: warnings.presence || transition_status.warnings,
        cohort_key: website.distillator_primary_cohort_key
      }
    end

    def normalize_mode(mode)
      return current_mode if mode.nil?

      mode.to_s
    end

    def failure(errors)
      Result.new(success?: false, website: website, from_mode: current_mode, to_mode: to_mode, warnings: [], blockers: blocked_transition_errors, errors: Array(errors))
    end

    def activation_error_message(message)
      normalized = message.to_s.sub(/\ANeeds review:\s*/i, "")
      "Cannot activate yet: #{normalized.sub(/\.\z/, '')}."
    end
  end
end
