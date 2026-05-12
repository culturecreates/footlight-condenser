module Distillator
  class BooleanParam
    TRUE_VALUES = [true, "true", "1", 1, :true].freeze
    FALSE_VALUES = [false, "false", "0", 0, nil, "", :false].freeze

    def self.true?(value)
      TRUE_VALUES.include?(value)
    end

    def self.false?(value)
      FALSE_VALUES.include?(value)
    end

    def self.parse(value)
      return true if true?(value)
      return false if false?(value)

      false
    end
  end
end
