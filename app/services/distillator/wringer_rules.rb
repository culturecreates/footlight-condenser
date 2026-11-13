module Distillator
  class WringerRules
    def self.all
      @all ||= load_rules
    end

    def self.reset!
      @all = nil
    end

    def self.find(key)
      all.find { |rule_key, _rule| rule_key.to_s == key.to_s }
    end

    def self.load_rules
      config_path = Rails.root.join("config/wringer.yml")
      unless File.exist?(config_path)
        Rails.logger.warn "[Wringer] Missing config/wringer.yml"
        return []
      end

      raw_yaml = ERB.new(File.read(config_path)).result
      parsed = YAML.safe_load(raw_yaml, aliases: true) || {}
      exceptions = parsed["system_exceptions"] || parsed[:system_exceptions]
      unless exceptions
        Rails.logger.warn "[Wringer] No system_exceptions configured"
        return []
      end

      exceptions.to_a
    end
    private_class_method :load_rules
  end
end
