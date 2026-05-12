#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

class DistillatorShadowLogSummary
  EVENTS = {
    compare: "distillator.fetch_shadow.compare",
    shadow_error: "distillator.fetch_shadow.error",
    ineligible: "distillator.fetch_mode.internal_ineligible",
    blocked: "DistillatorFetchBlocked"
  }.freeze

  attr_reader :path

  def self.call(path)
    new(path).call
  end

  def initialize(path)
    @path = path
  end

  def call
    summary = empty_summary

    File.foreach(path) do |line|
      parsed = parse_line(line)
      event = event_for(line, parsed)

      case event
      when EVENTS[:compare]
        summary[:total_comparisons] += 1
        if matched?(line, parsed)
          summary[:matched_count] += 1
        else
          summary[:mismatch_count] += 1
        end
        mismatch_fields(line, parsed).each do |field|
          summary[:mismatch_fields][field] += 1
        end
      when EVENTS[:shadow_error]
        summary[:shadow_errors_count] += 1
      when EVENTS[:ineligible]
        summary[:internal_ineligible_count] += 1
      end

      summary[:blocked_fetch_count] += 1 if line.include?(EVENTS[:blocked])
    end

    summary
  end

  def report
    summary = call
    lines = []
    lines << "Distillator shadow log summary"
    lines << "File: #{path}"
    lines << "Total comparisons: #{summary[:total_comparisons]}"
    lines << "Matched: #{summary[:matched_count]}"
    lines << "Mismatched: #{summary[:mismatch_count]}"
    lines << "Shadow errors: #{summary[:shadow_errors_count]}"
    lines << "Internal ineligible: #{summary[:internal_ineligible_count]}"
    lines << "Blocked fetches: #{summary[:blocked_fetch_count]}"
    lines << "Mismatch fields:"

    if summary[:mismatch_fields].empty?
      lines << "  none"
    else
      summary[:mismatch_fields].sort.each do |field, count|
        lines << "  #{field}: #{count}"
      end
    end

    lines.join("\n")
  end

  private

  def empty_summary
    {
      total_comparisons: 0,
      matched_count: 0,
      mismatch_count: 0,
      mismatch_fields: Hash.new(0),
      shadow_errors_count: 0,
      internal_ineligible_count: 0,
      blocked_fetch_count: 0
    }
  end

  def parse_line(line)
    json_start = line.index("{")
    return nil unless json_start

    JSON.parse(line[json_start..])
  rescue JSON::ParserError
    nil
  end

  def event_for(line, parsed)
    parsed_event = value_for(parsed, "event")
    return parsed_event if parsed_event

    EVENTS.values.find { |event| line.include?(event) }
  end

  def value_for(parsed, key)
    return unless parsed.is_a?(Hash)

    parsed[key] || parsed[key.to_sym]
  end

  def truthy?(value)
    value == true || value.to_s == "true"
  end

  def matched?(line, parsed)
    parsed_value = value_for(parsed, "matched")
    return truthy?(parsed_value) unless parsed_value.nil?

    line.match?(/:matched=>true\b/)
  end

  def mismatch_fields(line, parsed)
    fields = fields_from_json(parsed)
    return fields if fields.any?

    line.scan(/:field=>(?:"([^"]+)"|:([a-zA-Z0-9_]+)|([a-zA-Z0-9_]+))/).flatten.compact
  end

  def fields_from_json(parsed)
    mismatches = value_for(parsed, "mismatches")
    return [] unless mismatches.is_a?(Array)

    mismatches.filter_map do |mismatch|
      next unless mismatch.is_a?(Hash)

      value_for(mismatch, "field").to_s
    end.reject(&:empty?)
  end
end

if $PROGRAM_NAME == __FILE__
  path = ARGV.first
  unless path
    warn "Usage: ruby script/distillator_shadow_log_summary.rb PATH"
    exit 1
  end

  puts DistillatorShadowLogSummary.new(path).report
end
