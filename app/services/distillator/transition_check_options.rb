module Distillator
  class TransitionCheckOptions
    MAX_SAMPLE_SIZE = 1000
    SAMPLE_MODES = %w[default count all].freeze
    STRICTNESSES = %w[standard strict].freeze

    def self.coerce(value)
      value.is_a?(self) ? value : new(value.nil? ? {} : value)
    end

    attr_reader :sample_mode, :sample_size, :strictness

    def initialize(values = {})
      raise ArgumentError, "Check options must be an object" unless values.is_a?(Hash)
      values = values.to_h.stringify_keys
      raise ArgumentError, "Unknown check options" if (values.keys - %w[sample_mode sample_size strictness include_retired]).any?
      unless [nil, true, false, "true", "false"].include?(values["include_retired"])
        raise ArgumentError, "Historical audit must be true or false"
      end

      @sample_mode = values["sample_mode"].presence || "default"
      @strictness = values["strictness"].presence || "standard"
      @include_retired = values["include_retired"].to_s == "true"
      raise ArgumentError, "Choose a valid event sample" unless SAMPLE_MODES.include?(sample_mode)
      raise ArgumentError, "Choose a valid field comparison policy" unless STRICTNESSES.include?(strictness)
      @sample_mode = sample_mode.dup.freeze
      @strictness = strictness.dup.freeze
      if sample_mode == "count"
        @sample_size = begin
          Integer(values["sample_size"].to_s, 10)
        rescue ArgumentError, TypeError
          nil
        end
        unless sample_size && sample_size.between?(1, MAX_SAMPLE_SIZE)
          raise ArgumentError, "Fixed sample size must be a whole number between 1 and #{MAX_SAMPLE_SIZE}"
        end
      end
      freeze
    end

    def strict?
      strictness == "strict"
    end

    def default?
      sample_mode == "default" && !strict? && !include_retired?
    end

    def include_retired?
      @include_retired
    end

    def refresh_discovery?
      strict? && sample_mode.in?(%w[all count]) && !include_retired?
    end

    def size_for(total, default:)
      requested = case sample_mode
                  when "all" then total
                  when "count" then sample_size
                  else default
                  end
      [total, requested].min
    end

    def selection_rule(event_site: true)
      pages = if include_retired?
        "archived publishable event pages with public URLs"
      elsif event_site
        "active publishable event pages with public URLs"
      else
        "website pages"
      end
      case sample_mode
      when "all" then "All #{pages}."
      when "count" then "Up to #{sample_size} #{pages}."
      else
        return "20% of #{pages}, minimum 5, capped at 25." if include_retired?

        event_site ? TransitionCheck::SELECTION_RULE : "Up to 3 website pages."
      end
    end

    def field_policy_label
      strict? ? "Strict: differences in any selected field block activation" : "Standard: core field differences block; other differences warn"
    end

    def to_h
      { "sample_mode" => sample_mode, "strictness" => strictness }.tap do |values|
        values["sample_size"] = sample_size if sample_mode == "count"
        values["include_retired"] = true if include_retired?
      end
    end
  end
end
