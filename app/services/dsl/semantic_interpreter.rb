module Dsl
  class SemanticInterpreter
    def annotate(steps)
      previous_output = nil

      Array(steps).map do |step|
        source = step.respond_to?(:to_h) ? step.to_h : step
        normalized_step = source.is_a?(Hash) ? source.with_indifferent_access : {}
        current_output = normalized_step[:output]

        interpreted_semantic = semantic(previous_output, current_output)
        interpreted_delta = delta(previous_output, current_output, interpreted_semantic)
        interpreted_intent = intent(normalized_step)

        previous_output = current_output

        normalized_step.merge(
          semantic: interpreted_semantic,
          delta: interpreted_delta,
          intent: interpreted_intent
        )
      end
    end

    # State-only semantic classification.
    def semantic(previous, current)
      if previous.nil?
        blank?(current) ? "No result" : "Δ added"
      elsif blank?(current) && blank?(previous)
        "No result"
      elsif current == previous
        "No change"
      elsif present?(current) && blank?(previous)
        "Δ added"
      elsif blank?(current) && present?(previous)
        "Δ removed"
      else
        "Δ changed"
      end
    end

    # Secondary diff details for changed states only.
    def delta(previous, current, semantic_value)
      return nil unless semantic_value == "Δ changed"

      compute_delta(previous, current)
    end

    def intent(step)
      source = step.respond_to?(:to_h) ? step.to_h : step
      normalized_step = source.is_a?(Hash) ? source.with_indifferent_access : {}

      type = normalized_step[:type].to_s
      code = normalized_step[:code].to_s

      return "navigation" if type == "url"
      return "extraction" if type == "xpath"
      return "conditional extraction" if type == "if_xpath"

      if type == "ruby"
        return "filter" if code.include?("reject") || code.include?("select")
        return "transform" if code.include?("map") || code.include?("gsub")

        return "transform"
      end

      "unknown"
    end

    private

    def blank?(value)
      return true if value.nil? || value == [] || value == ""
      return true if value.is_a?(String) && value.strip == "[]"

      false
    end

    def present?(value)
      !blank?(value)
    end

    def compute_delta(previous, current)
      if previous.is_a?(Array) && current.is_a?(Array)
        return compute_array_delta(previous, current)
      end

      if previous.is_a?(String) && current.is_a?(String)
        previous_array = parse_summary_array_state(previous)
        current_array = parse_summary_array_state(current)
        return compute_array_delta(previous_array, current_array) if previous_array && current_array
        return nil if previous == current

        return "changed"
      end

      previous_array = Array(previous).map(&:to_s)
      current_array = Array(current).map(&:to_s)
      compute_array_delta(previous_array, current_array)
    end

    def compute_array_delta(previous_array, current_array)
      added = current_array - previous_array
      removed = previous_array - current_array

      parts = []
      parts << "+#{added.first(2).map { |v| truncate_delta(v) }.join(', ')}" if added.any?
      parts << "-#{removed.first(2).map { |v| truncate_delta(v) }.join(', ')}" if removed.any?

      return nil if parts.empty?

      parts.join(" ")
    end

    def parse_summary_array_state(value)
      return [] if value == "[]"
      return nil unless value.is_a?(String)

      match = value.match(/\A\[\d+ items:\s*(.*)\]\z/)
      return nil unless match

      body = match[1].to_s.strip
      return [] if body.empty?

      body.split(/\s*,\s*/)
    end

    def truncate_delta(value)
      string_value = value.to_s
      string_value.length > 60 ? "#{string_value[0, 60]}..." : string_value
    end
  end
end
