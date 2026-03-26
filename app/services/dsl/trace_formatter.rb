# frozen_string_literal: true

module Dsl
  class TraceFormatter
    MAX_STRING_LENGTH = 200
    ARRAY_SAMPLE_SIZE = 5
    MAX_UI_EVENTS = 20
    MAX_SESSION_BYTES = 3000

    class << self
      def normalize(raw_events)
        return [] unless raw_events.is_a?(Array)

        raw_events.map do |evt|
          output_full = evt[:output_full] || evt["output_full"]
          input_full  = evt[:input_full]  || evt["input_full"]

          output_full ||= evt[:output_preview] || evt["output_preview"]
          input_full  ||= evt[:input_preview]  || evt["input_preview"]

          {
            step: evt[:step] || evt["step"],
            type: evt[:type] || evt["type"],
            code: evt[:code] || evt["code"],
            input_preview: evt[:input_preview] || evt["input_preview"] || [],
            output_preview: evt[:output_preview] || evt["output_preview"] || [],
            input_full: input_full,
            output_full: output_full,
            probe: evt[:probe] || evt["probe"],
            url_before: (evt[:url_before] || evt["url_before"] || "").to_s,
            url_after: (evt[:url_after] || evt["url_after"] || "").to_s,
            duration_ms: evt[:duration_ms] || evt["duration_ms"] || 0,
            error_class: evt[:error_class] || evt["error_class"],
            error_message: evt[:error_message] || evt["error_message"],
            wringer: evt[:wringer] || evt["wringer"]
          }
        end
      end

      def for_session_v2(trace)
        return { version: 2, initial: { state: nil, url: nil }, urls: [], steps: [] } unless trace.is_a?(Array)

        normalized = trace.each_with_index.map do |event, index|
          normalize_event_for_session(event, index)
        end

        compact = build_session_v2(
          normalized,
          code_limit: 40,
          error_code_limit: 120,
          output_limit: 80,
          initial_limit: 80,
          include_duration: true
        )
        return compact if serialized_size(compact) <= MAX_SESSION_BYTES

        Rails.logger.warn("[DSL TRACE] v2 trace exceeded session budget; trimming non-critical fields")

        compact = build_session_v2(
          normalized,
          code_limit: 40,
          error_code_limit: 120,
          output_limit: 40,
          initial_limit: 40,
          include_duration: false
        )
        return compact if serialized_size(compact) <= MAX_SESSION_BYTES

        build_session_v2(
          normalized,
          code_limit: 20,
          error_code_limit: 80,
          output_limit: 20,
          initial_limit: 20,
          include_duration: false
        )
      end

      def for_session(trace)
        return { version: 1, urls: [], events: [] } unless trace.is_a?(Array)

        urls = []
        events = trace.each_with_index.map do |event, index|
          compact_event_for_session(event, urls, index)
        end

        compact = { version: 1, urls: urls, events: events }
        return compact if serialized_size(compact) <= MAX_SESSION_BYTES

        Rails.logger.warn("[DSL TRACE] Compact trace exceeded session budget; trimming non-critical fields")

        reduced_events = events.map do |event|
          reduced = event.dup
          unless reduced.key?(:e)
            reduced.delete(:i)
            reduced.delete(:o)
            reduced.delete(:d)
          end
          reduced[:c] = truncate_str(reduced[:c], 40) if reduced.key?(:c)
          reduced
        end

        compact = { version: 1, urls: urls, events: reduced_events }
        return compact if serialized_size(compact) <= MAX_SESSION_BYTES

        final_events = reduced_events.map do |event|
          final = event.dup
          final[:c] = truncate_str(final[:c], 20) if final.key?(:c) && !final.key?(:e)
          final
        end

        { version: 1, urls: urls, events: final_events }
      end

      def for_ui(trace)
        return [] unless trace.is_a?(Array)

        formatted = trace.map do |event|
          formatted_event = format_event(event)

          if formatted_event.nil?
            Rails.logger.warn("[DSL TRACE] Dropped malformed event: #{event.inspect}")
          end

          formatted_event
        end.compact
        limit_for_session(formatted)
      end

      def format_event(event)
        raw = event.respond_to?(:to_h) ? event.to_h : event
        return nil unless raw.is_a?(Hash)

        payload = raw.with_indifferent_access
        error_text = [format_value(payload[:error_class]), format_value(payload[:error_message])].compact.join(": ").presence

        {
          step: payload[:step],
          type: format_value(payload[:type]),
          code: format_value(payload[:code]),
          input: format_value(first_present(payload, :input, :input_preview)),
          output: format_value(first_present(payload, :output, :output_preview)),
          error: error_text,
          url_before: format_value(payload[:url_before]),
          url_after: format_value(payload[:url_after]),
          duration_ms: payload[:duration_ms]
        }
      rescue StandardError => e
        Rails.logger.debug { "[DSL] skipped malformed trace event: #{e.class}: #{e.message}" }
        nil
      end

      def format_value(value)
        return nil if value.nil?

        case value
        when Exception
          truncate_str(value.message.to_s)
        when Array
          sample = value.first(ARRAY_SAMPLE_SIZE).map { |entry| format_value(entry) }
          truncate_str("[Array size=#{value.size}, sample=#{sample.inspect}]")
        when String
          truncate_str(value)
        when Hash
          truncate_str(value.inspect)
        else
          truncate_str(value.inspect)
        end
      rescue StandardError
        truncate_str(value.to_s)
      end

      def truncate_str(str, max = MAX_STRING_LENGTH)
        string = str.to_s
        return string if string.length <= max

        "#{string[0, max]}..."
      end

      private

      def normalize_event_for_session(event, fallback_step_index)
        raw = event.respond_to?(:to_h) ? event.to_h : event
        payload = raw.is_a?(Hash) ? raw.with_indifferent_access : {}

        {
          step: payload[:step].nil? ? fallback_step_index + 1 : payload[:step],
          type: payload[:type].nil? ? nil : payload[:type].to_s,
          code: payload[:code].nil? ? nil : payload[:code].to_s,
          input: summarize_for_session(first_present(payload, :input, :input_preview), max: 120),
          output: summarize_for_session(first_present(payload, :output, :output_preview), max: 120),
          probe: normalize_probe_for_session(payload[:probe]),
          wringer: normalize_wringer_for_session(payload[:wringer]),
          url_before: normalize_session_url(payload[:url_before]),
          url_after: normalize_session_url(payload[:url_after]),
          duration_ms: payload[:duration_ms],
          error: session_error_text(payload)
        }
      rescue StandardError => e
        Rails.logger.warn("[DSL TRACE] Failed to normalize trace event for session: #{e.class}: #{e.message}")
        {
          step: fallback_step_index + 1,
          type: nil,
          code: nil,
          input: nil,
          output: nil,
          url_before: nil,
          url_after: nil,
          duration_ms: nil,
          error: "Trace normalization error: #{e.class}"
        }
      end

      def build_session_v2(normalized, code_limit:, error_code_limit:, output_limit:, initial_limit:, include_duration:)
        first = normalized.first || {}
        initial_state = first[:input].nil? ? nil : truncate_str(first[:input], initial_limit)
        initial_url = first[:url_before]

        urls = []
        current_url = initial_url

        steps = normalized.map do |event|
          step_payload = {}
          severity = event_severity(event)
          step_payload[:s] = event[:step]
          step_payload[:t] = truncate_str(event[:type], 30) if event[:type].present?

          if event[:code].present?
            code_max = severity == :error ? error_code_limit : code_limit
            step_payload[:c] = truncate_str(event[:code], code_max)

            if severity != :ok
              step_payload[:cf] = truncate_str(event[:code], error_code_limit)
            end
          end

          if event[:output].present?
            step_payload[:o] = truncate_str(event[:output], output_limit)

            if severity == :error
              step_payload[:of] = truncate_str(event[:output], output_limit * 2)
            elsif severity == :warning
              step_payload[:of] = truncate_str(event[:output], output_limit)
            end
          elsif event[:output] == "[]"
            step_payload[:o] = "[]"
            step_payload[:of] = "[]" if severity != :ok
          end

          if event[:probe].is_a?(Hash)
            if event[:probe][:skipped]
              step_payload[:p] = { sk: true }
            else
              probe_result = event[:probe][:result] || {}
              step_payload[:p] = {
                st: probe_result[:status],
                x: probe_result[:xpath],
                o: probe_result[:output],
                ok: event[:probe][:ok]
              }.compact
            end
          end

          if event[:wringer].is_a?(Hash)
            step_payload[:w] = {
              i: event[:wringer][:inherited],
              et: event[:wringer][:error_type],
              r: event[:wringer][:retry],
              c: event[:wringer][:cache],
              u: event[:wringer][:unreachable],
              r404: event[:wringer][:received_404],
              se: event[:wringer][:system_error],
              pa: event[:wringer][:policy_action],
              s: event[:wringer][:signals],
              h: event[:wringer][:hints],
              fu: event[:wringer][:final_url],
              rc: event[:wringer][:redirect_chain]
            }.compact
          end

          next_url = event[:url_after] || current_url
          if next_url.present? && next_url != current_url
            step_payload[:ua] = url_index_for_session(urls, next_url)
            current_url = next_url
          end

          step_payload[:d] = event[:duration_ms] if include_duration && !event[:duration_ms].nil?
          step_payload[:e] = event[:error] if event[:error].present?

          step_payload
        end

        {
          version: 2,
          initial: { state: initial_state, url: initial_url },
          urls: urls,
          steps: steps
        }
      end

      def event_severity(event)
        return :error if event[:error].present?

        output_empty = event[:output].to_s == "[]"

        probe_used =
          event[:probe].is_a?(Hash) && !event[:probe][:skipped]

        wringer_issue =
          event[:wringer].is_a?(Hash) && (
            event[:wringer][:error_type].present? ||
            event[:wringer][:unreachable] ||
            event[:wringer][:system_error]
          )

        return :warning if output_empty || probe_used || wringer_issue

        :ok
      end

      def normalize_session_url(value)
        return nil if value.nil?

        url = value.to_s
        return nil if url.empty?

        url
      end

      def compact_event_for_session(event, urls, fallback_step_index)
        raw = event.respond_to?(:to_h) ? event.to_h : event
        payload = raw.is_a?(Hash) ? raw.with_indifferent_access : {}

        error_text = session_error_text(payload)
        error_step = error_text.present?
        code_limit = error_step ? 200 : 80

        compact = {}
        compact[:s] = payload[:step].nil? ? fallback_step_index + 1 : payload[:step]

        type = payload[:type]
        compact[:t] = truncate_str(type.to_s, 30) unless type.nil?

        code = payload[:code]
        compact[:c] = truncate_str(code.to_s, code_limit) unless code.nil?

        input_summary = summarize_for_session(first_present(payload, :input, :input_preview))
        compact[:i] = input_summary unless input_summary.nil?

        output_summary = summarize_for_session(first_present(payload, :output, :output_preview))
        compact[:o] = output_summary unless output_summary.nil?

        before_index = url_index_for_session(urls, payload[:url_before])
        compact[:ub] = before_index unless before_index.nil?

        after_index = url_index_for_session(urls, payload[:url_after])
        compact[:ua] = after_index unless after_index.nil?

        duration = payload[:duration_ms]
        compact[:d] = duration unless duration.nil?

        compact[:e] = error_text if error_text.present?

        compact
      rescue StandardError => e
        Rails.logger.warn("[DSL TRACE] Failed to compact trace event: #{e.class}: #{e.message}")
        { s: fallback_step_index + 1, e: "Trace compaction error: #{e.class}" }
      end

      def summarize_for_session(value, max: 80)
        return nil if value.nil?

        if value.is_a?(Array)
          return "[]" if value.empty?

          sample = value.first(2).map { |entry| truncate_str(entry.to_s, 60) }
          "[#{value.size} items: #{sample.join(', ')}]"
        else
          truncate_str(value.to_s, max)
        end
      end

      def normalize_probe_for_session(value)
        raw = value.respond_to?(:to_h) ? value.to_h : value
        return { skipped: true } unless raw.is_a?(Hash)

        payload = raw.with_indifferent_access
        return { skipped: true } if payload[:skipped]

        probe_result =
          if payload[:result].is_a?(Hash)
            payload[:result].with_indifferent_access
          else
            payload
          end

        xpath = probe_result[:xpath].to_s
        return { skipped: true } if xpath.blank?

        status = probe_result[:status].to_s
        status = "ok" if status.blank?
        output = Array(probe_result[:output]).compact.map { |entry| truncate_str(entry.to_s, 80) }.first(3)

        {
          result: {
            status: status,
            xpath: truncate_str(xpath, 40),
            output: output
          }.compact,
          ok: payload.key?(:ok) ? payload[:ok] : (status == "ok")
        }.compact
      rescue StandardError
        { skipped: true }
      end

      def normalize_wringer_for_session(value)
        raw = value.respond_to?(:to_h) ? value.to_h : value
        return { inherited: true } unless raw.is_a?(Hash)

        payload = raw.with_indifferent_access
        return { inherited: true } if payload[:inherited]

        {
          error_type: payload[:error_type],
          retry: payload[:retry],
          cache: payload[:cache],
          unreachable: payload[:unreachable],
          received_404: payload[:received_404],
          system_error: payload[:system_error],
          policy_action: payload[:policy_action],
          signals: payload[:signals].is_a?(Hash) ? payload[:signals] : nil,
          hints: payload[:hints].is_a?(Array) ? payload[:hints] : nil
        }.compact
      end

      def session_error_text(payload)
        explicit_error = payload[:error]
        return explicit_error.to_s if explicit_error.present?

        [payload[:error_class], payload[:error_message]].compact.join(": ").presence
      end

      def url_index_for_session(urls, value)
        return nil if value.nil?

        url = value.to_s
        return nil if url.empty?

        existing_index = urls.index(url)
        return existing_index unless existing_index.nil?

        urls << url
        urls.length - 1
      end

      def first_present(hash, *keys)
        keys.each do |key|
          value = hash[key]
          return value unless value.nil?
        end
        nil
      end

      def limit_for_session(events)
        return events if serialized_size(events) <= MAX_SESSION_BYTES

        Rails.logger.warn("[DSL TRACE] Trace too large, truncating fields (not steps)")

        events.map do |e|
          e.merge(
            code: truncate_str(e[:code], 80),
            input: truncate_str(e[:input], 80),
            output: truncate_str(e[:output], 80),
            error: truncate_str(e[:error], 120)
          )
        end
      end

      def serialized_size(payload)
        JSON.generate(payload).bytesize
      rescue StandardError
        payload.to_s.bytesize
      end
    end
  end
end
