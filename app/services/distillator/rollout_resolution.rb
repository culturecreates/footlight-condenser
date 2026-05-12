module Distillator
  class RolloutResolution < Struct.new(
    :execution_mode,
    :rollout_mode,
    :active_backend,
    :source,
    :requested_mode,
    :website_id,
    keyword_init: true
  )
    def self.from_mode(mode:, source:, requested_mode: nil, website_id: nil)
      normalized_mode = mode.to_sym

      new(
        execution_mode: normalized_mode,
        rollout_mode: rollout_mode_for(normalized_mode),
        active_backend: active_backend_for(normalized_mode),
        source: source,
        requested_mode: requested_mode&.to_sym,
        website_id: website_id,
      )
    end

    def self.rollout_mode_for(mode)
      mode.to_sym == :internal ? :active : mode.to_sym
    end

    def self.active_backend_for(mode)
      mode.to_sym == :internal ? :condenser : :wringer
    end
  end
end
