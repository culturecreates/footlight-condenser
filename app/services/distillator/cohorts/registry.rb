require "yaml"

module Distillator
  module Cohorts
    class Registry
      def self.path
        Rails.root.join("config/distillator_cohorts.yml")
      end

      def self.all
        @all ||= load_file(path)
      end

      def self.fetch(key)
        all[key.to_s]
      end

      def self.keys
        all.keys
      end

      def self.reload!
        @all = nil
        all
      end

      def self.load_file(file_path)
        return {} unless File.exist?(file_path)

        raw = YAML.safe_load(File.read(file_path), aliases: false) || {}
        raw.each_with_object({}) do |(key, value), acc|
          next unless value.is_a?(Hash)

          acc[key.to_s] = {
            key: key.to_s,
            label: value["label"].to_s.presence || key.to_s.humanize,
            source_url: value["source_url"].to_s.presence,
            match_fields: Array(value["match_fields"]).map(&:to_s),
            feed_names: Array(value["feed_names"]).map(&:to_s)
          }
        end
      rescue StandardError
        {}
      end
    end
  end
end
