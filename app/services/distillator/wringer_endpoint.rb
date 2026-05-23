require "uri"

module Distillator
  class WringerEndpoint
    LOCAL_COMPATIBILITY_BASE_URL = "http://localhost:3000".freeze
    LOCAL_LEGACY_BASE_URL = "http://localhost:3009".freeze

    Result = Struct.new(
      :compatibility_base_url,
      :legacy_lookup_base_url,
      :state,
      :status_label,
      :status_detail,
      keyword_init: true
    ) do
      def missing_config?
        state == :missing_config
      end

      def local_development?
        state == :local_development
      end

      def remote_configured?
        state == :remote_configured
      end

      def unreachable?
        state == :unreachable
      end
    end

    def self.current(last_error: nil)
      new(last_error: last_error).call
    end

    def initialize(config: Rails.application.config.x.distillator, env: Rails.env, last_error: nil)
      @config = config
      @env = env.to_s
      @last_error = last_error
    end

    def call
      compatibility = configured_compatibility_base_url
      legacy_lookup = configured_legacy_lookup_base_url(compatibility)

      if compatibility.present?
        return build_remote_result(compatibility, legacy_lookup)
      end

      return build_local_result if allow_localhost_default?

      build_missing_config_result
    end

    private

    attr_reader :config, :env, :last_error

    def allow_localhost_default?
      return config.allow_localhost_compatibility if [true, false].include?(config.allow_localhost_compatibility)

      env == "development"
    end

    def configured_compatibility_base_url
      normalize_base_url(config.compatibility_base_url)
    end

    def configured_legacy_lookup_base_url(compatibility)
      normalize_base_url(config.legacy_wringer_base_url) || compatibility
    end

    def build_remote_result(compatibility, legacy_lookup)
      state = last_error.present? ? :unreachable : :remote_configured
      label =
        if state == :unreachable
          "Current Wringer: Unreachable"
        else
          "Current Wringer: Remote configured"
        end

      detail =
        if state == :unreachable
          "last lookup failed"
        else
          sanitize_display_url(compatibility)
        end

      Result.new(
        compatibility_base_url: compatibility,
        legacy_lookup_base_url: legacy_lookup,
        state: state,
        status_label: label,
        status_detail: detail
      )
    end

    def build_local_result
      Result.new(
        compatibility_base_url: LOCAL_COMPATIBILITY_BASE_URL,
        legacy_lookup_base_url: normalize_base_url(config.legacy_wringer_base_url) || LOCAL_LEGACY_BASE_URL,
        state: :local_development,
        status_label: "Current Wringer: Local development",
        status_detail: sanitize_display_url(LOCAL_COMPATIBILITY_BASE_URL)
      )
    end

    def build_missing_config_result
      detail =
        if env == "staging"
          "comparisons disabled"
        else
          "legacy lookup unavailable"
        end

      label =
        if env == "staging"
          "Current Wringer: Missing staging config"
        else
          "Current Wringer: Missing config"
        end

      Result.new(
        compatibility_base_url: nil,
        legacy_lookup_base_url: nil,
        state: :missing_config,
        status_label: label,
        status_detail: detail
      )
    end

    def normalize_base_url(value)
      url = value.to_s.strip
      return nil if url.blank?

      url.sub(%r{/\z}, "")
    end

    def sanitize_display_url(value)
      uri = URI.parse(value.to_s)
      return value.to_s if uri.scheme.blank? || uri.host.blank?

      "#{uri.scheme}://#{uri.host}#{uri.port ? port_suffix(uri) : ''}"
    rescue URI::InvalidURIError
      value.to_s
    end

    def port_suffix(uri)
      return "" if (uri.scheme == "http" && uri.port == 80) || (uri.scheme == "https" && uri.port == 443)

      ":#{uri.port}"
    end
  end
end
