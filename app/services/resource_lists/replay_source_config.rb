# frozen_string_literal: true

require "json"

module ResourceLists
  # A read-only, independently exported configuration for replaying an existing
  # selected ResourceList Source. It is data, never an invented extraction rule.
  class ReplaySourceConfig
    LABELS = ["Webpage URL List", "URI List"].freeze
    attr_reader :source_id, :website_id, :website_seedurl, :property_label, :algorithm_value, :render_js

    def self.from_file(path)
      new(JSON.parse(File.binread(path)))
    end

    def initialize(data)
      raise ArgumentError, "Expected JSON Source object" unless data.is_a?(Hash)
      @source_id = positive_integer!(data, "source_id")
      @website_id = positive_integer!(data, "website_id")
      @website_seedurl = nonempty_string!(data, "website_seedurl")
      @property_label = data.fetch("property_label")
      raise ArgumentError, "Expected a ResourceList list Source" unless LABELS.include?(@property_label)
      raise ArgumentError, "Expected selected Source" unless data.fetch("selected") == true
      @render_js = data.fetch("render_js")
      raise ArgumentError, "Invalid render_js boolean" unless [true, false].include?(@render_js)
      @algorithm_value = nonempty_string!(data, "algorithm_value")
    end

    private

    def positive_integer!(data, key)
      value = data.fetch(key)
      raise ArgumentError, "Invalid #{key}" unless value.is_a?(Integer) && value.positive?
      value
    end

    def nonempty_string!(data, key)
      value = data.fetch(key)
      raise ArgumentError, "Invalid #{key}" unless value.is_a?(String) && !value.strip.empty?
      value
    end
  end
end
