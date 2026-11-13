module Distillator
  class TransitionRuntime
    APP_NAME_KEYS = %w[HEROKU_APP_NAME APP_NAME HEROKU_PARENT_APP_NAME].freeze
    STAGING_RUNTIME_VALUES = %w[staging].freeze
    STAGING_ENV_VALUES = %w[staging].freeze
    STAGING_ALLOWED_ROLLOUT_MODES = %w[shadow active].freeze

    STAGING_APP_NAMES = %w[
      footlight-condenser-test-c24c162bb7c8
    ].freeze

    def self.staging?
      explicit_staging_runtime? || explicit_staging_environment? || known_staging_app?
    end

    def self.allow_active_override?
      explicit_override_enabled? || Rails.env.test? || staging?
    end

    def self.known_staging_app?
      app_names.any? { |name| STAGING_APP_NAMES.include?(name.to_s) }
    end

    def self.staging_invalid_rollout_mode_scope(scope = Website.all)
      scope.where.not(distillator_mode: STAGING_ALLOWED_ROLLOUT_MODES)
           .or(scope.where(distillator_mode: [nil, ""]))
    end

    def self.staging_rollout_mode_invalid?(mode)
      !STAGING_ALLOWED_ROLLOUT_MODES.include?(mode.to_s)
    end

    def self.app_names
      APP_NAME_KEYS.filter_map { |key| ENV[key].presence }
    end

    def self.explicit_override_enabled?
      ENV["DISTILLATOR_ALLOW_ACTIVE_OVERRIDE"].to_s == "true"
    end

    def self.explicit_staging_runtime?
      STAGING_RUNTIME_VALUES.include?(ENV["DISTILLATOR_RUNTIME"].to_s)
    end

    def self.explicit_staging_environment?
      STAGING_ENV_VALUES.include?(ENV["RAILS_ENV"].to_s)
    end
  end
end
