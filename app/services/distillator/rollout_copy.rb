module Distillator
  module RolloutCopy
    STATE_UI = {
      legacy: {
        label: "Legacy Wringer active",
        css_class: "rollout-badge-legacy",
        description: "Wringer remains the production fetch path."
      },
      shadow: {
        label: "Shadow comparison",
        css_class: "rollout-badge-shadow",
        description: "Wringer serves production results; Condenser compares in the background."
      },
      active: {
        label: "Condenser active",
        css_class: "rollout-badge-active",
        description: "Condenser serves fetch/cache results; legacy Wringer remains available for inspection."
      },
      replay: {
        label: "Replay diagnostic",
        css_class: "rollout-badge-replay",
        description: "Replay mode is diagnostic only and may not represent live production fetches."
      },
      unknown: {
        label: "Unknown rollout",
        css_class: "rollout-badge-unknown",
        description: "Rollout state could not be determined from the current context."
      }
    }.freeze

    CACHE_ACTION_COPY = {
      active_cache_label: "Open active cache",
      condenser_cache_label: "Open Condenser cache",
      legacy_inspection_label: "Inspect legacy Wringer",
      compare_label: "Compare Condenser vs Wringer"
    }.freeze

    FORM_OPTION_LABELS = {
      legacy: "Legacy - Wringer active",
      shadow: "Shadow - Wringer production path + Condenser comparison",
      active: "Active - Condenser active"
    }.freeze

    INDEX_FILTER_OPTION_LABELS = {
      all: "All rollout modes",
      legacy: "Legacy - Wringer active",
      shadow: "Shadow - comparison",
      active: "Active - Condenser active",
      replay: "Replay - diagnostic",
      unknown: "Unknown / unset"
    }.freeze

    ROLLOUT_PANEL_TITLE = "Fetch rollout".freeze

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
      STATE_UI.fetch(normalize(mode), STATE_UI.fetch(:unknown))
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
        [INDEX_FILTER_OPTION_LABELS.fetch(:replay), "replay"],
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
        "Inspect legacy Wringer when validating parity."
      when :shadow
        "Compare Condenser output before promotion."
      when :legacy
        "Inspect Condenser cache before promotion."
      when :replay
        "Use replay output only for diagnostics."
      else
        "Confirm rollout configuration before promotion decisions."
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
  end
end
