module Distillator
  class FetchMode
    Resolution = Struct.new(:mode, :source, keyword_init: true)

    # See docs/rollout_modes.md for the operator-vs-internal glossary.
    # Fetch execution modes are Distillator runtime paths.
    # Website rollout state lives separately on Website::DISTILLATOR_MODES.
    EXECUTION_MODES = %w[legacy internal shadow].freeze
    ALIASES = { "active" => "internal" }.freeze
    DEFAULT_MODE = "internal"
    SAFE_DEFAULT_MODE = "legacy"

    def self.current
      parse(ENV.fetch("DISTILLATOR_FETCH_MODE", DEFAULT_MODE))
    end

    def self.parse(value)
      mode = value.to_s.strip.downcase
      return DEFAULT_MODE.to_sym if mode.blank?

      # Website rollout uses "active"; runtime execution remains :internal.
      mode = ALIASES.fetch(mode, mode)

      EXECUTION_MODES.include?(mode) ? mode.to_sym : DEFAULT_MODE.to_sym
    end

    def self.resolve(explicit_mode: nil, website: nil, website_id: nil, log_context: {})
      resolution(
        explicit_mode: explicit_mode,
        website: website,
        website_id: website_id,
        log_context: log_context
      ).mode
    end

    def self.rollout_mode(explicit_mode: nil, website: nil, website_id: nil, log_context: {})
      rollout_resolution(
        explicit_mode: explicit_mode,
        website: website,
        website_id: website_id,
        log_context: log_context
      ).mode
    end

    def self.resolution(explicit_mode: nil, website: nil, website_id: nil, log_context: {})
      resolved = rollout_resolution_object(
        explicit_mode: explicit_mode,
        website: website,
        website_id: website_id,
        log_context: log_context
      )

      Resolution.new(mode: resolved.execution_mode, source: resolved.source)
    end

    def self.rollout_resolution(explicit_mode: nil, website: nil, website_id: nil, log_context: {})
      resolved = rollout_resolution_object(
        explicit_mode: explicit_mode,
        website: website,
        website_id: website_id,
        log_context: log_context
      )

      Resolution.new(mode: resolved.rollout_mode, source: resolved.source)
    end

    def self.rollout_resolution_object(explicit_mode: nil, website: nil, website_id: nil, log_context: {})
      return Distillator::RolloutResolution.from_mode(mode: :replay, source: :replay) if ENV["REPLAY_FETCH"].present?
      return Distillator::RolloutResolution.from_mode(mode: parse(explicit_mode), source: :explicit, requested_mode: explicit_mode) if explicit_mode.present?

      website_record, source = website_record_for(
        website: website,
        website_id: website_id,
        log_context: log_context
      )
      if website_record.respond_to?(:distillator_fetch_mode)
        return Distillator::RolloutResolution.from_mode(
          mode: website_record.distillator_fetch_mode,
          source: source,
          website_id: website_record.id
        )
      end

      env_mode = env_resolution_without_website
      return env_mode if env_mode

      Distillator::RolloutResolution.from_mode(mode: SAFE_DEFAULT_MODE, source: :default)
    end

    def self.legacy?
      current == :legacy
    end

    def self.internal?
      current == :internal
    end

    def self.shadow?
      current == :shadow
    end

    def self.normalize_log_context(log_context)
      return {} unless log_context.respond_to?(:to_h)

      log_context.to_h.symbolize_keys
    end
    private_class_method :normalize_log_context

    def self.website_record_for(website:, website_id:, log_context:)
      return [website, :website] if website.respond_to?(:distillator_fetch_mode)

      website_record = website_from_id(website_id)
      return [website_record, :website_id] if website_record

      context_website_id = normalize_log_context(log_context)[:website_id]
      website_record = website_from_id(context_website_id)
      return [website_record, :website_id] if website_record

      [nil, nil]
    end
    private_class_method :website_record_for

    def self.env_resolution_without_website
      raw_mode = ENV["DISTILLATOR_FETCH_MODE"]
      return nil if raw_mode.nil?

      parsed_mode = parse(raw_mode)
      return Distillator::RolloutResolution.from_mode(mode: :legacy, source: :env, requested_mode: raw_mode) if parsed_mode == :legacy && raw_mode.to_s.strip.present?

      nil
    end
    private_class_method :env_resolution_without_website

    def self.website_from_id(website_id)
      return if website_id.blank?

      Website.find_by(id: website_id)
    end
    private_class_method :website_from_id
  end
end
