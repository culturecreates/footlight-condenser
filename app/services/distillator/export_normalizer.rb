require "json"

module Distillator
  class ExportNormalizer
    VOLATILE_KEYS = %w[
      cache_changed
      cache_refreshed
      created_at
      dateModified
      generatedAt
      recorded_at
      updated_at
    ].freeze

    VOLATILE_LINE_PATTERN = /
      (cache_changed|cache_refreshed|created_at|dateModified|generatedAt|recorded_at|updated_at)
    /ix.freeze

    def self.normalize(value)
      new(value).normalize
    end

    def self.blank_export?(value)
      normalized = normalize(value)
      normalized.blank? || %w[[] {}].include?(normalized)
    rescue StandardError
      value.blank?
    end

    def initialize(value)
      @value = value
    end

    def normalize
      parsed = parse_json(@value)
      return normalize_json(parsed) if parsed

      normalize_lines(@value)
    end

    private

    def parse_json(value)
      return value if value.is_a?(Hash) || value.is_a?(Array)

      JSON.parse(value.to_s)
    rescue JSON::ParserError
      nil
    end

    def normalize_json(value)
      JSON.pretty_generate(canonicalize(value))
    end

    def canonicalize(value)
      case value
      when Hash
        value
          .reject { |key, _| VOLATILE_KEYS.include?(key.to_s) }
          .sort_by { |key, _| key.to_s }
          .each_with_object({}) do |(key, child), out|
            out[key.to_s] = canonicalize(child)
          end
      when Array
        value.map { |child| canonicalize(child) }
             .sort_by { |child| JSON.generate(child) }
      when String
        normalize_whitespace(value)
      else
        value
      end
    end

    def normalize_lines(value)
      value
        .to_s
        .lines
        .map { |line| normalize_whitespace(line) }
        .reject(&:blank?)
        .reject { |line| line.match?(VOLATILE_LINE_PATTERN) }
        .sort
        .join("\n")
    end

    def normalize_whitespace(value)
      value.to_s.gsub(/\s+/, " ").strip
    end
  end
end
