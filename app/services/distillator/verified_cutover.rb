module Distillator
  class VerifiedCutover
    EVENT = "rollout.cutover_confirmed"

    Record = Struct.new(:completed_at, :event, keyword_init: true)

    def self.for_websites(website_ids, baselines: {})
      latest_events = RolloutEvent.where(website_id: website_ids)
        .select("DISTINCT ON (website_id) distillator_rollout_events.*").order(:website_id, id: :desc)
        .index_by(&:website_id)

      website_ids.each_with_object({}) do |id, cutovers|
        event = latest_events[id]
        if event&.readiness_snapshot&.fetch("event", nil) == EVENT
          cutovers[id] = Record.new(completed_at: Time.iso8601(event.readiness_snapshot.fetch("completed_at")), event: event)
        elsif (baseline = baselines[id]) &&
            (event.nil? || (event.to_mode == "active" && event.created_at <= baseline.created_at))
          # Preserve cutovers already recorded by the original migration baseline.
          cutovers[id] = Record.new(completed_at: baseline.created_at)
        end
      end
    end

    def self.confirm!(website:, completed_at:, actor:, evidence:)
      unless completed_at && completed_at <= Time.current && actor.present? && evidence.present?
        raise ArgumentError, "Provide a past or current cutover date, an operator, and a reference to the handoff evidence"
      end

      website.with_lock do
        unless website.distillator_mode == "active" && FetchMode.rollout_resolution_object(website: website).active_backend == :condenser
          raise ArgumentError, "The website must currently serve through Condenser"
        end
        if SiteTransition.active.exists?(website_id: website.id)
          raise ArgumentError, "Wait for the current site transition to finish before recording the handoff"
        end

        latest = website.rollout_events.order(id: :desc).first
        if latest&.readiness_snapshot&.fetch("event", nil) == EVENT
          next latest
        end
        if latest && (latest.to_mode != "active" || completed_at < latest.created_at)
          raise ArgumentError, "The cutover must belong to the website's current Active rollout"
        end

        event = website.rollout_events.create!(from_mode: "active", to_mode: "active", actor: actor, reason: evidence,
          readiness_snapshot: {
            event: EVENT, completed_at: completed_at.iso8601(6), backend: "condenser", activation_event_id: latest&.id
          })
        MigrationBaseline.capture!(website)
        event
      end
    end
  end
end
