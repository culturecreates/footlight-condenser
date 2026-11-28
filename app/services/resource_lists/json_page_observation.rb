# frozen_string_literal: true

require "digest"
require "json"

module ResourceLists
  # Inspect one observed JSON response without presuming its event schema.
  # Provides diagnostics only. Neither a valid JSON response nor an empty
  # array proves that a ResourceList refresh is complete or can be retired.
  class JsonPageObservation
    MAX_BYTES = 8_000_000
    Result = Struct.new(:status, :errors, :top_level, :top_keys, :arrays, :sha256, :bytes,
      keyword_init: true) do
      def json_observed? = status == "json_observed"
    end

    def self.call(http_status:, content_type:, body:, max_bytes: MAX_BYTES)
      return failure("invalid_limit") unless max_bytes.is_a?(Integer) && max_bytes.positive?
      return failure("untrusted_http_status") unless http_status == 200
      return failure("missing_body") unless body.is_a?(String) && !body.empty?
      return failure("oversized_body") if body.bytesize > max_bytes
      return failure("unexpected_content_type") unless content_type.to_s.downcase.match?(
        %r{\Aapplication/(?:json|[\w.+-]+\+json)(?:\s*;|\s*\z)})

      begin
        parsed = JSON.parse(body)
      rescue JSON::ParserError, Encoding::InvalidByteSequenceError
        return failure("invalid_json")
      end
      return failure("unstructured_json") unless parsed.is_a?(Hash) || parsed.is_a?(Array)

      arrays = []
      visit = lambda do |node, path, depth|
        return if depth > 4 || arrays.length >= 30
        if node.is_a?(Array)
          example = node.first
          arrays << { path:, length: node.length, item_type: kind(example),
            first_item_keys: example.is_a?(Hash) ? example.keys.first(15) : [] }
        elsif node.is_a?(Hash)
          node.each do |key, value|
            next unless value.is_a?(Hash) || value.is_a?(Array)
            visit.call(value, "#{path}.#{key}", depth + 1)
            break if arrays.length >= 30
          end
        end
      end
      visit.call(parsed, "$", 0)
      Result.new(status: "json_observed", errors: [], top_level: kind(parsed),
        top_keys: parsed.is_a?(Hash) ? parsed.keys.first(25) : [], arrays: arrays,
        sha256: Digest::SHA256.hexdigest(body), bytes: body.bytesize)
    end

    def self.kind(value)
      case value
      when Hash then "object"
      when Array then "array"
      when NilClass then "null"
      when String then "string"
      when Numeric then "number"
      when TrueClass, FalseClass then "boolean"
      else "unknown"
      end
    end

    def self.failure(code)
      Result.new(status: "inconclusive", errors: [code], top_level: nil,
        top_keys: [], arrays: [], sha256: nil, bytes: nil)
    end
    private_class_method :failure
  end
end
