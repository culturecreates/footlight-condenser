module Distillator
  class ProductionPreflight
    class Failure < StandardError; end

    Entry = Struct.new(:label, :value, :ok, keyword_init: true) do
      def to_output
        "#{label}: #{value}"
      end
    end

    Result = Struct.new(:entries, keyword_init: true) do
      def ok?
        entries.all?(&:ok)
      end
    end

    REQUIRED_ROLLOUT_MODES = %w[legacy shadow active].freeze

    def self.call
      new.call
    end

    def call
      Result.new(
        entries: [
          database_entry,
          queue_adapter_entry,
          rollout_modes_entry,
          default_mode_entry,
          cache_table_entry,
          transition_report_route_entry,
          compare_route_entry,
          wringer_inspection_entry
        ]
      )
    end

    private

    def database_entry
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.execute("SELECT 1")
      end

      Entry.new(label: "Database", value: "OK", ok: true)
    rescue StandardError => e
      Entry.new(label: "Database", value: "FAILED (#{e.message})", ok: false)
    end

    def queue_adapter_entry
      adapter = ActiveJob::Base.queue_adapter_name.to_s.presence || "unknown"
      Entry.new(label: "Queue adapter", value: adapter, ok: adapter != "unknown")
    end

    def rollout_modes_entry
      modes = Website::DISTILLATOR_MODES
      expected = REQUIRED_ROLLOUT_MODES.join("/")
      if modes == REQUIRED_ROLLOUT_MODES
        Entry.new(label: "Rollout modes", value: "#{expected} available", ok: true)
      else
        Entry.new(label: "Rollout modes", value: "FAILED (found #{modes.join('/')})", ok: false)
      end
    end

    def default_mode_entry
      mode = Distillator::FetchMode.rollout_resolution_object.rollout_mode.to_s
      safe = mode == "legacy"
      suffix = safe ? "" : " (unsafe)"

      Entry.new(label: "Default mode", value: "#{mode}#{suffix}", ok: safe)
    end

    def cache_table_entry
      ok = Distillator::FetchCache.table_exists?
      Entry.new(label: "Cache table", value: ok ? "OK" : "FAILED (missing)", ok: ok)
    rescue StandardError => e
      Entry.new(label: "Cache table", value: "FAILED (#{e.message})", ok: false)
    end

    def transition_report_route_entry
      path = Rails.application.routes.url_helpers.distillator_shadow_report_path
      Entry.new(label: "Transition Report route", value: path.present? ? "OK" : "FAILED (missing)", ok: path.present?)
    rescue StandardError => e
      Entry.new(label: "Transition Report route", value: "FAILED (#{e.message})", ok: false)
    end

    def compare_route_entry
      path = Rails.application.routes.url_helpers.condenser_cache_compare_path(uri: "http://example.org")
      Entry.new(label: "Compare route", value: path.present? ? "OK" : "FAILED (missing)", ok: path.present?)
    rescue StandardError => e
      Entry.new(label: "Compare route", value: "FAILED (#{e.message})", ok: false)
    end

    def wringer_inspection_entry
      base = ApplicationController.helpers.get_wringer_url_per_environment.to_s.strip
      configured = base.present?
      value = configured ? "configured" : "missing"

      Entry.new(label: "Wringer inspection base", value: value, ok: configured)
    rescue StandardError => e
      Entry.new(label: "Wringer inspection base", value: "FAILED (#{e.message})", ok: false)
    end
  end
end
