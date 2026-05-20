module Distillator
  class TransitionRuntime
    APP_NAME_KEYS = %w[HEROKU_APP_NAME APP_NAME HEROKU_PARENT_APP_NAME HEROKU_SLUG_COMMIT].freeze
    STAGING_TOKENS = %w[staging stage test qa review].freeze

    def self.allow_active_override?
      return true if ENV["DISTILLATOR_ALLOW_ACTIVE_OVERRIDE"].to_s == "true"
      return true if Rails.env.test?
      return true if Rails.env.staging? && heroku_runtime?
      return true if known_staging_or_test_app_name?

      false
    end

    def self.heroku_runtime?
      ENV["DYNO"].present? || ENV["HEROKU_APP_NAME"].present? || ENV["HEROKU_RELEASE_VERSION"].present?
    end

    def self.known_staging_or_test_app_name?
      app_names.any? do |name|
        normalized = name.to_s.downcase
        STAGING_TOKENS.any? { |token| normalized.include?(token) }
      end
    end

    def self.app_names
      APP_NAME_KEYS.filter_map { |key| ENV[key].presence }
    end
  end
end
