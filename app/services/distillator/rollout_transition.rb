module Distillator
  class RolloutTransition
    Result = Struct.new(:success?, :website, :from_mode, :to_mode, :warnings, :blockers, :errors, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(website:, to_mode:, actor: nil, reason: nil, force: false, override: false, review: false, attributes: {})
      @website = website
      @raw_to_mode = to_mode
      @to_mode = normalize_mode(to_mode)
      @actor = actor
      @reason = normalize_reason(reason)
      @force = force
      @override = override
      @review = review
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
          readiness_snapshot: readiness_snapshot(warnings),
          event: rollout_event_name
        )
        return Result.new(success?: true, website: website, from_mode: from_mode, to_mode: to_mode, warnings: warnings, blockers: [], errors: [])
      end

      failure(website.errors.full_messages)
    end

    private

    attr_reader :website, :to_mode, :actor, :reason, :force, :override, :review, :attributes, :raw_to_mode

    def current_mode
      website.distillator_mode.presence || "legacy"
    end

    def invalid_current_mode?
      !Website::DISTILLATOR_MODES.include?(current_mode)
    end

    def valid_target_mode?
      Website::DISTILLATOR_MODES.include?(to_mode)
    end

    def blocked_transition_errors
      @blocked_transition_errors ||= begin
        override_errors = explicit_override_errors
        return override_errors if override_errors.any?
        return [] if current_mode == to_mode
        return [] if invalid_current_mode? && to_mode == "shadow"
        return [] if current_mode == "legacy" && to_mode == "shadow"
        return [] if current_mode == "shadow" && to_mode == "legacy"
        return [] if current_mode == "active" && to_mode.in?(%w[legacy shadow])
        return legacy_to_active_errors if current_mode == "legacy" && to_mode == "active"
        return shadow_to_active_errors if current_mode == "shadow" && to_mode == "active"

        ["Unsupported rollout transition"]
      end
    end

    def legacy_to_active_errors
      return [] if override_requested? && Distillator::TransitionRuntime.allow_active_override?

      ["Direct legacy to active promotion is blocked"]
    end

    def shadow_to_active_errors
      return review_to_active_errors if review_requested?
      return [] if override_requested? && Distillator::TransitionRuntime.allow_active_override?
      return [] if promotion_readiness.blockers.blank? && promotion_readiness.warnings.blank?

      return promotion_readiness.blockers if promotion_readiness.blockers.any?
      return promotion_readiness.warnings.map { |message| activation_error_message(message) } if promotion_readiness.warnings.any?

      ["Cannot activate yet: checks are not complete."]
    end

    def transition_warnings
      []
    end

    def promotion_readiness
      @promotion_readiness ||= Distillator::PromotionReadiness.call(
        website: website,
        cache: Distillator::ShadowReportQuery.latest_cache_for_website(website),
        evidence_by_kind: website.latest_transition_evidences_by_kind
      )
    end

    def readiness_snapshot(warnings)
      {
        blockers: promotion_readiness.blockers,
        warnings: warnings.presence || promotion_readiness.warnings,
        cohort_key: website.distillator_primary_cohort_key,
        override: override_requested?,
        review_activation: review_requested?,
        manual_review_required: promotion_readiness.respond_to?(:manual_review_required) ? promotion_readiness.manual_review_required : nil,
        review_needed_fields: promotion_readiness.respond_to?(:review_needed_fields) ? promotion_readiness.review_needed_fields : [],
        safety: promotion_readiness.respond_to?(:safety) ? promotion_readiness.safety : nil,
        confidence: promotion_readiness.respond_to?(:confidence) ? promotion_readiness.confidence : nil,
        comparison_policy: promotion_readiness.respond_to?(:comparison_policy) ? promotion_readiness.comparison_policy : nil
      }
    end

    def explicit_override_errors
      return [] unless override_requested?
      return ["Activate anyway is not allowed in this runtime"] unless Distillator::TransitionRuntime.allow_active_override?
      return ["Reason is required for Activate anyway"] if reason.blank?

      []
    end

    def review_to_active_errors
      return ["Reason is required for Activate after review"] if reason.blank?
      return ["Activate after review is available only for review-needed parity differences."] unless promotion_readiness.respond_to?(:review_activation_eligible) && promotion_readiness.review_activation_eligible

      []
    end

    def normalize_mode(mode)
      return current_mode if mode.nil?

      mode.to_s
    end

    def failure(errors)
      Result.new(success?: false, website: website, from_mode: current_mode, to_mode: to_mode, warnings: [], blockers: blocked_transition_errors, errors: Array(errors))
    end

    def override_requested?
      override || force
    end

    def review_requested?
      review == true
    end

    def rollout_event_name
      return "rollout.review_activate" if review_requested?
      return "rollout.override" if override_requested?

      nil
    end

    def activation_error_message(message)
      normalized = message.to_s.sub(/\ANeeds review:\s*/i, "")
      "Cannot activate yet: #{normalized.sub(/\.\z/, '')}."
    end

    def normalize_reason(value)
      trimmed = value.to_s.strip
      trimmed.presence
    end
  end
end
