module Distillator
  class TransitionRuntime
    APP_NAME_KEYS = %w[HEROKU_APP_NAME APP_NAME HEROKU_PARENT_APP_NAME].freeze

    STAGING_APP_NAMES = %w[
      footlight-condenser-test-c24c162bb7c8
    ].freeze

    def self.allow_active_override?
      explicit_override_enabled? || Rails.env.test? || known_staging_or_test_app_name?
    end

    def self.known_staging_or_test_app_name?
      app_names.any? { |name| STAGING_APP_NAMES.include?(name.to_s) }
    end

    def self.app_names
      APP_NAME_KEYS.filter_map { |key| ENV[key].presence }
    end

    def self.explicit_override_enabled?
      ENV["DISTILLATOR_ALLOW_ACTIVE_OVERRIDE"].to_s == "true"
    end
  end
end
