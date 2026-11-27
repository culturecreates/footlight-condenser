module Distillator
  class RolloutEventRecorder
    def self.call(...)
      new(...).call
    end

    def initialize(website:, from_mode:, to_mode:, actor: nil, reason: nil, readiness_snapshot: {}, event: nil)
      @website = website
      @from_mode = from_mode
      @to_mode = to_mode
      @actor = actor
      @reason = reason
      @readiness_snapshot = readiness_snapshot
      @event = event
    end

    def call
      return if from_mode.to_s == to_mode.to_s

      Distillator::RolloutEvent.create!(
        website: website,
        from_mode: from_mode,
        to_mode: to_mode,
        actor: actor.presence,
        reason: reason.presence,
        readiness_snapshot: event_snapshot
      )
    end

    private

    attr_reader :website, :from_mode, :to_mode, :actor, :reason, :readiness_snapshot, :event

    def event_snapshot
      readiness_snapshot.to_h.merge(
        "event" => event.presence || inferred_event
      )
    end

    def inferred_event
      return "rollout.rollback" if rollback?

      "rollout.transition"
    end

    def rollback?
      from_mode.to_s == "active" && to_mode.to_s == "legacy"
    end
  end
end
