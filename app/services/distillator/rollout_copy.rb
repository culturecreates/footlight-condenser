module Distillator
  module RolloutCopy
    PRODUCTION_STATE_UI = {
      legacy: {
        label: "Legacy",
        css_class: "rollout-badge-legacy",
        description: "Wringer serves production."
      },
      shadow: {
        label: "Shadow",
        css_class: "rollout-badge-shadow",
        description: "Wringer serves production while Condenser is checked in the background."
      },
      active: {
        label: "Active",
        css_class: "rollout-badge-active",
        description: "Condenser serves production while Wringer stays available for diagnostics."
      }
    }.freeze

    DIAGNOSTIC_STATE_UI = {
      replay: {
        label: "Unknown",
        css_class: "rollout-badge-replay",
        description: "Diagnostic mode only. Do not treat this as a production state."
      },
      unknown: {
        label: "Unknown",
        css_class: "rollout-badge-unknown",
        description: "Production mode could not be determined from the current context."
      }
    }.freeze

    CACHE_ACTION_COPY = {
      active_cache_label: "Open active cache",
      condenser_cache_label: "Open Condenser cache",
      legacy_inspection_label: "Inspect legacy Wringer",
      compare_label: "Compare Condenser vs Wringer"
    }.freeze

    FORM_OPTION_LABELS = {
      legacy: "Legacy",
      shadow: "Shadow",
      active: "Active"
    }.freeze

    INDEX_FILTER_OPTION_LABELS = {
      all: "All production modes",
      legacy: "Legacy",
      shadow: "Shadow",
      active: "Active",
      replay: "Unknown",
      unknown: "Unknown"
    }.freeze

    ROLLOUT_PANEL_TITLE = "Production mode".freeze

    def self.label(mode)
      state(mode)[:label]
    end

    def self.description(mode)
      state(mode)[:description]
    end

    def self.css_class(mode)
      state(mode)[:css_class]
    end

    def self.state(mode)
      all_states.fetch(normalize(mode), DIAGNOSTIC_STATE_UI.fetch(:unknown))
    end

    def self.production_states
      PRODUCTION_STATE_UI
    end

    def self.diagnostic_states
      DIAGNOSTIC_STATE_UI
    end

    def self.active_cache_label
      CACHE_ACTION_COPY.fetch(:active_cache_label)
    end

    def self.condenser_cache_label
      CACHE_ACTION_COPY.fetch(:condenser_cache_label)
    end

    def self.legacy_inspection_label
      CACHE_ACTION_COPY.fetch(:legacy_inspection_label)
    end

    def self.compare_label
      CACHE_ACTION_COPY.fetch(:compare_label)
    end

    def self.website_form_options
      [
        [FORM_OPTION_LABELS.fetch(:legacy), "legacy"],
        [FORM_OPTION_LABELS.fetch(:shadow), "shadow"],
        [FORM_OPTION_LABELS.fetch(:active), "active"]
      ]
    end

    def self.website_index_filter_options
      [
        [INDEX_FILTER_OPTION_LABELS.fetch(:all), nil],
        [INDEX_FILTER_OPTION_LABELS.fetch(:legacy), "legacy"],
        [INDEX_FILTER_OPTION_LABELS.fetch(:shadow), "shadow"],
        [INDEX_FILTER_OPTION_LABELS.fetch(:active), "active"],
        [INDEX_FILTER_OPTION_LABELS.fetch(:unknown), "unknown"]
      ]
    end

    def self.rollout_panel_title
      ROLLOUT_PANEL_TITLE
    end

    def self.active_backend_label(mode)
      case normalize(mode)
      when :active, :replay
        "Condenser"
      when :shadow, :legacy
        "Wringer"
      else
        "Unknown"
      end
    end

    def self.next_step(mode)
      case normalize(mode)
      when :active
        "Monitor production and use Legacy if rollback is needed."
      when :shadow
        "Review diagnostics, then promote to Active when ready."
      when :legacy
        "Move to Shadow before promotion."
      when :replay
        "Use diagnostics only. Keep production on Legacy, Shadow, or Active."
      else
        "Confirm the production mode before making rollout decisions."
      end
    end

    def self.normalize(mode)
      case mode.to_s
      when "legacy"
        :legacy
      when "shadow"
        :shadow
      when "active", "internal"
        :active
      when "replay"
        :replay
      else
        :unknown
      end
    end

    def self.all_states
      @all_states ||= PRODUCTION_STATE_UI.merge(DIAGNOSTIC_STATE_UI).freeze
    end
  end
end
