module Distillator
  class OperatorNextAction
    STALE_OR_UNKNOWN_STATUSES = %i[stale missing inconclusive not_evaluated blocked_by_fetch].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(website:, transition_status:, cache_link_payload: nil)
      @website = website
      @transition_status = transition_status
      @cache_link_payload = cache_link_payload || {}
    end

    def call
      return "Review blocker." if blockers?
      return "Move to Shadow." if mode == :legacy
      return "Run transition check." if transition_check_needed?
      return "Activate after review." if mode == :shadow && review_activation_eligible?
      return "Promote to Active." if mode == :shadow && ready?

      if mode == :active && ready?
        return "Open active cache." if active_cache_available?

        return "Monitor."
      end

      "Monitor."
    end

    private

    attr_reader :website, :transition_status, :cache_link_payload

    def mode
      Distillator::RolloutCopy.normalize(website&.distillator_mode)
    end

    def ready?
      transition_status.status == :ready
    end

    def review_activation_eligible?
      transition_status.respond_to?(:review_activation_eligible) && transition_status.review_activation_eligible
    end

    def blockers?
      Array(transition_status.blockers).any?
    end

    def transition_check_needed?
      return true if transition_status.status == :not_checked

      [transition_status.fetch, transition_status.statements, transition_status.export].any? do |status|
        STALE_OR_UNKNOWN_STATUSES.include?(status)
      end
    end

    def active_cache_available?
      cache_link_payload[:active_cache_url].present?
    end
  end
end
