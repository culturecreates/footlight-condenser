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
      raise ArgumentError, "Unknown check options" if (values.keys - %w[sample_mode sample_size strictness]).any?

      @sample_mode = values["sample_mode"].presence || "default"
      @strictness = values["strictness"].presence || "standard"
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
      sample_mode == "default" && !strict?
    end

    def size_for(total, default:)
      requested = case sample_mode
                  when "all" then total
                  when "count" then sample_size
                  else default
                  end
      [total, requested].min
    end

    def selection_rule
      case sample_mode
      when "all" then "All publishable event pages, or all website pages when none are publishable."
      when "count" then "Up to #{sample_size} publishable event pages, or website pages when none are publishable."
      else Distillator::TransitionCheck::SELECTION_RULE
      end
    end

    def field_policy_label
      strict? ? "Strict: differences in any selected field block activation" : "Standard: core field differences block; other differences warn"
    end

    def to_h
      { "sample_mode" => sample_mode, "strictness" => strictness }.tap do |values|
        values["sample_size"] = sample_size if sample_mode == "count"
      end
    end
  end
end
