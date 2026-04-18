# app/services/dsl/core/algorithm_runner.rb
module Dsl
  module Core
    class AlgorithmRunner
    HALT = Object.new

    StepTrace = Struct.new(
      :step,
      :type,
      :code,
      :input,
      :output,
      :error,
      :url_before,
      :url_after,
      :duration_ms,
      keyword_init: true
    )

    def initialize(ctx)
      @url         = ctx[:url]
      @render_js   = ctx[:render_js]
      @scrape_opts = ctx[:scrape_options] || {}
      @tracer      = ctx[:tracer]
      @agent       = Mechanize.new
      @agent.user_agent_alias = 'Mac Safari'
      @html        = nil
      @page        = nil
      @json        = nil
      @graph       = nil
    end

    def abort_structure?(obj)
      obj.is_a?(Array) &&
        obj.length == 2 &&
        obj.first == "abort_update" &&
        obj.last.is_a?(Hash)
    end

    def run(algorithm)
      results = []
      previous_locals = snapshot_thread_locals

      # reset thread-local DSL state for this run
      Thread.current[:dsl_array] = []
      Thread.current[:dsl_url]   = @url
      Thread.current[:dsl_json]  = nil

      @dsl_binding = binding

      steps = algorithm.split(';').map(&:strip).reject(&:empty?)
      previous_prefix = nil
      previous_step_index = nil
      @probed_url_step_indices = []

      steps.each_with_index do |raw, idx|
        prefix, code = raw.partition('=').values_at(0, 2)
        step_index  = idx + 1

        @current_wringer_status = nil
        input_copy  = Marshal.load(Marshal.dump(results))
        url_before  = @url
        start_time  = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # === UPDATE THREAD-LOCALS BEFORE EVERY STEP ===
        Thread.current[:dsl_array] = results
        Thread.current[:dsl_url]   = @url
        Thread.current[:dsl_json]  = @json

        out = execute(prefix, code, results)
        input_preview = trace_preview(input_copy)

        # handle abort payload
        if abort_structure?(out)
          end_time    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          duration_ms = ((end_time - start_time) * 1000).round(1)

          @tracer.step(
            step: step_index,
            type: prefix,
            code: code,
            input: input_preview,
            output: [],
            input_full: input_copy,
            output_full: [],
            probe: trace_probe_payload(nil),
            error: out.last,           # error message details
            wringer: trace_wringer_payload,
            url_before: url_before,
            url_after: @url,
            duration_ms: duration_ms
          )

          return out
        end

        if halt_structure?(out)
          end_time    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          duration_ms = ((end_time - start_time) * 1000).round(1)
          results     = out.last

          @tracer.step(
            step: step_index,
            type: prefix,
            code: code,
            input: input_preview,
            output: trace_preview(results),
            input_full: input_copy,
            output_full: results,
            probe: trace_probe_payload(nil),
            error: nil,
            wringer: trace_wringer_payload,
            url_before: url_before,
            url_after: @url,
            duration_ms: duration_ms
          )

          break
        end

        end_time    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration_ms = ((end_time - start_time) * 1000).round(1)

        url_after   = @url
        output      = trace_preview(out)
        probe       = build_xpath_probe(previous_prefix, prefix, out, previous_step_index)
        if abort_structure?(probe)
          @tracer.step(
            step: step_index,
            type: prefix,
            code: code,
            input: input_preview,
            output: [],
            input_full: input_copy,
            output_full: [],
            probe: trace_probe_payload(nil),
            error: probe.last,
            wringer: trace_wringer_payload,
            url_before: url_before,
            url_after: url_after,
            duration_ms: duration_ms
          )

          return probe
        end

        @tracer.step(
          step: step_index,
          type: prefix,
          code: code,
          input: input_preview,
          output: output,
          input_full: input_copy,
          output_full: out,
          probe: trace_probe_payload(probe),
          error: nil,
          wringer: trace_wringer_payload,
          url_before: url_before,
          url_after: url_after,
          duration_ms: duration_ms
        )

        results = out
        previous_prefix = prefix
        previous_step_index = step_index
      rescue StandardError, SyntaxError => e
        end_time    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration_ms = ((end_time - start_time) * 1000).round(1)

        @tracer.step(
          step: step_index,
          type: prefix,
          code: code,
          input: input_preview,
          output: [],
          input_full: input_copy,
          output_full: [],
          probe: trace_probe_payload(nil),
          error: e,
          wringer: trace_wringer_payload,
          url_before: url_before,
          url_after: @url,
          duration_ms: duration_ms
        )
        return abort_update(
          error: e.message,
          error_type: e.class.to_s,
          step: prefix
        )
      end

      results
    ensure
      restore_thread_locals(previous_locals)
    end

    private

    def execute(prefix, code, arr)
      case prefix

      # accumulate = map + flatMap
      # accumulate context:
      # - $e     = current item
      # - $array = [current item]
      # - $url   = current item
      when 'accumulate'
        execute_accumulate(code, arr)

      when 'sparql'
        begin
          @graph ||= RDF::Graph.load(use_wringer(@url, @render_js, @scrape_opts))
          sparql = "PREFIX schema: <http://schema.org/> select * where #{code}"
          rows = SPARQL.execute(sparql, @graph)
          [*(rows.count == 1 ? rows.first.answer.value : rows.map { |r| r.answer.value })]
        rescue StandardError => e
          abort_update(error: e.message, error_type: e.class.to_s, step: 'sparql')
        end

      when 'url'           then handle_url_step(code, arr, step: 'url')

      when 'renderjs_url'  then handle_url_step(code, arr, render_js: true, step: 'renderjs_url')

      when 'post_url'
        temp_opts = @scrape_opts.merge(json_post: true).merge(force_scrape_every_hrs: 1)
        handle_url_step(code, arr, opts: temp_opts, step: 'post_url')

      when 'json_url'
        result = resolve_and_fetch_url(code, arr, step: 'json_url')
        return result if abort_structure?(result)

        apply_json_text_result(result)

        arr

      when 'api'
        new_url = resolve_url_only(code, arr, step: 'api')
        return new_url if abort_structure?(new_url)

        data = HTTParty.get(new_url)
        raise "API error #{data.code}" unless data.code.to_s.start_with?('2')

        JSON.parse(data.body)

      when 'xpath'
        execute_xpath(code)

      when 'xpath_sanitize'
        page_status = ensure_page!(step: 'xpath_sanitize')
        return page_status if abort_structure?(page_status)

        @page.xpath(code).map do |node|
          sanitize(node.to_s,
                   tags: %w[h1 h2 h3 h4 h5 h6 p li ul ol strong em a i br],
                   attributes: %w[href])
        end

      when 'if_xpath'
        page_status = ensure_page!(step: 'if_xpath')
        return page_status if abort_structure?(page_status)

        nodes = @page.xpath(code)
        return [HALT, arr] if nodes.blank?

        nodes.map { |n| n.text.to_s.squish }.reject(&:blank?)

      when 'unless_xpath'
        page_status = ensure_page!(step: 'unless_xpath')
        return page_status if abort_structure?(page_status)

        nodes = @page.xpath(code)
        return [HALT, arr] if nodes.present?

        arr

      when 'css'
        page_status = ensure_page!(step: 'css')
        return page_status if abort_structure?(page_status)

        @page.css(code).map { |n| n.text.to_s.squish }.reject(&:blank?)

      when 'json'
        page_status = ensure_page!(step: 'json')
        return page_status if abort_structure?(page_status)

        text = @page.respond_to?(:text) ? @page.text : @html.to_s
        @json ||= JSON.parse(text)
        Thread.current[:dsl_json] = @json
        @dsl_binding.eval(sub(code, arr))

      when 'time_zone'
        ["time_zone: #{code}"]

      when 'ruby'
        # update thread-locals before eval
        Thread.current[:dsl_array] = arr
        Thread.current[:dsl_url]   = @url
        Thread.current[:dsl_json]  = @json

        result = @dsl_binding.eval(sub(code, arr))

        # sync back DSL state
        @url  = Thread.current[:dsl_url]
        @json = Thread.current[:dsl_json]

        result

      when 'manual'
        [code]

      else
        raise "Missing DSL prefix: #{prefix}=#{code}"
      end
    end

    def build_xpath_probe(previous_prefix, current_prefix, output, previous_step_index = nil)
      return nil unless previous_prefix == 'url'
      return nil unless current_prefix == 'xpath'
      return nil if output.present?
      return nil if previous_step_index.nil?

      @probed_url_step_indices ||= []
      return nil if @probed_url_step_indices.include?(previous_step_index)

      probe_result = execute_xpath("//title")
      if abort_structure?(probe_result)
        return probe_result
      end

      probe_output = Array(probe_result).compact.map(&:to_s).first(3)
      @probed_url_step_indices << previous_step_index

      {
        status: "ok",
        xpath: "//title",
        output: probe_output
      }
    rescue StandardError
      @probed_url_step_indices << previous_step_index if previous_step_index

      {
        status: "error",
        exception: true,
        xpath: "//title",
        output: []
      }
    end

    def resolve_and_fetch_url(code, arr, render_js: @render_js, opts: @scrape_opts, step: 'url')
      raw = @dsl_binding.eval(sub(code, arr))
      new_url = Dsl::Support::UrlResolver.extract(raw)
      if new_url.blank?
        Rails.logger.warn { "[DSL] abort invalid URL from #{raw.inspect}" }
        return abort_update(
          error: "Invalid URL resolved from #{raw.inspect}",
          error_type: "InvalidURL",
          step: step
        )
      end

      Rails.logger.debug { "[DSL] #{code} → #{new_url}" }

      @url = new_url

      fetch_result = wringer_client.fetch(url: @url, render_js: render_js, scrape_options: opts)
      @current_wringer_status =
        (fetch_result[:wringer] || {}).merge(
          duration_ms: fetch_result[:duration_ms]
        )
      raw = fetch_result[:body]

      if fetch_result[:status] == :abort
        Rails.logger.warn("[DSL] abort on #{new_url} (#{@current_wringer_status&.dig(:error_type)})")
        return normalize_abort_result(raw, step: step)
      end

      raw
    end

    def resolve_url_only(code, arr, step: 'url')
      raw = @dsl_binding.eval(sub(code, arr))
      new_url = Dsl::Support::UrlResolver.extract(raw)
      return new_url if new_url.present?

      abort_update(
        error: "Invalid URL resolved from #{raw.inspect}",
        error_type: "InvalidURL",
        step: step
      )
    end

    def apply_html_result(html)
      @html = html
      @page = Nokogiri::HTML(@html, nil, Encoding::UTF_8.to_s)
      @json = nil
      Thread.current[:dsl_json] = nil
    end

    def apply_json_text_result(text)
      @html = text
      @page = Struct.new(:text).new(@html)
      @json = nil
      Thread.current[:dsl_json] = nil
    end

    def handle_url_step(code, arr, render_js: false, opts: @scrape_opts, step: 'url')
      result = resolve_and_fetch_url(code, arr, render_js: render_js, opts: opts, step: step)
      return result if abort_structure?(result)

      apply_html_result(result)
      arr
    end

    def execute_xpath(code)
      page_status = ensure_page!(step: 'xpath')
      return page_status if abort_structure?(page_status)

      #@page.xpath(code).map(&:text)
      # new default behavior
      @page.xpath(code).map { |n| node_value(n).to_s.squish }.reject(&:blank?)
    end

    def halt_structure?(obj)
      obj.is_a?(Array) &&
        obj.length == 2 &&
        obj.first.equal?(HALT)
    end

    # Rewrite DSL references into thread-locals
    def sub(code, _)
      code.to_s
          .gsub('$array', 'Thread.current[:dsl_array]')
          .gsub('$url',   'Thread.current[:dsl_url]')
          .gsub('$json',  'Thread.current[:dsl_json]')
          .gsub(/\$e\b/, 'Thread.current[:dsl_item]') 
    end

    def ensure_page!(step: nil)
      return :ok if @page

      fetch_result = wringer_client.fetch(url: @url, render_js: @render_js, scrape_options: @scrape_opts)
      @current_wringer_status =
        (fetch_result[:wringer] || {}).merge(
          duration_ms: fetch_result[:duration_ms]
        )
      raw = fetch_result[:body]

      if fetch_result[:status] == :abort
        return normalize_abort_result(raw, step: step)
      end

      @html = raw
      @page = Nokogiri::HTML(@html, nil, Encoding::UTF_8.to_s)
      :ok
    end

    def abort_update(error:, error_type:, step: nil, source: "dsl_runner")
      payload = {
        error: error.to_s,
        error_type: error_type.to_s,
        source: source
      }
      payload[:step] = step if step.present?
      ["abort_update", payload]
    end

    def normalize_abort_result(result, step: nil)
      payload =
        if abort_structure?(result)
          result.last.respond_to?(:to_h) ? result.last.to_h.dup : {}
        else
          {}
        end

      error = payload[:error] || payload["error"] || "DSL runner abort"
      error_type = payload[:error_type] || payload["error_type"] || "DslAbort"
      normalized = payload.transform_keys { |k| k.respond_to?(:to_sym) ? k.to_sym : k }
      effective_step = normalized[:step].presence || step
      effective_source = normalized[:source].presence || "dsl_runner"

      built = abort_update(
        error: error,
        error_type: error_type,
        step: effective_step,
        source: effective_source
      ).last

      # Preserve upstream metadata (retry/cache/signals/etc.) while enforcing the shared abort shape.
      ["abort_update", built.merge(normalized.except(:error, :error_type, :step, :source))]
    end

    def use_wringer(u, rj, opt)
      return ApplicationController.helpers.use_wringer(u, rj, opt) unless rj == false && (opt.blank? || opt == { force_scrape_every_hrs: nil })
      return ApplicationController.helpers.use_wringer(u, rj, opt) unless CcWringerHelper.respond_to?(:use_wringer)

      url = u
      client_result = WringerClient.fetch(url)
      Rails.logger.info(
        "[WringerClient] url=#{url} status=#{client_result[:status]} duration=#{client_result[:duration_ms]}ms"
      )

      if client_result[:status] == :ok
          client_result[:html]
      else
          ["abort_update", {
            error_type: client_result.dig(:error, :type),
            error: client_result.dig(:error, :message)
          }]
      end
    end

    def safe_wringer_call(&blk)
      ApplicationController.helpers.safe_wringer_call(&blk)
    end

    def wringer_client
      @wringer_client ||= Dsl::Support::WringerClient.new(
        agent: @agent,
        render_js: @render_js,
        scrape_options: @scrape_opts,
        use_wringer: method(:use_wringer),
        safe_wringer_call: method(:safe_wringer_call),
        logger: Rails.logger
      )
    end

    def node_value(n)
      n.respond_to?(:value) ? n.value : n.text
    end

    def sanitize(*args)
      ApplicationController.helpers.sanitize(*args)
    end

    def trace_preview(value)
      value.is_a?(Array) ? value.flatten(1) : [value]
    end

    def trace_wringer_payload
      wringer = @current_wringer_status.is_a?(Hash) ? @current_wringer_status.dup : {}
      wringer = wringer.transform_keys { |k| k.respond_to?(:to_sym) ? k.to_sym : k }
      wringer[:signals] = {} unless wringer[:signals].is_a?(Hash)
      wringer[:hints] = [] unless wringer[:hints].is_a?(Array)
      wringer[:inherited] = true if wringer.blank?
      wringer[:inherited] = true if @current_wringer_status.blank?
      wringer
    end

    def trace_probe_payload(probe_result)
      return { skipped: true } unless probe_result.present?

      {
        result: probe_result,
        ok: probe_result[:status].to_s == "ok"
      }
    end

    def maybe_expand(url)
      return url unless needs_expansion?(url)

      Dsl::Network::UrlExpander.call(url, agent: @agent)
    end

    def extract_id(url)
      Dsl::Identity::UrlIdentifier.call(url, @params)
    end

    def fallback_id(url)
      Dsl::Identity::UrlFallback.id(url)
    end

    def execute_accumulate(code, arr)
      return [] if arr.blank?

      arr.flat_map do |item|
        prev_item  = Thread.current[:dsl_item]
        prev_array = Thread.current[:dsl_array]
        prev_url   = Thread.current[:dsl_url]
        prev_json  = Thread.current[:dsl_json]

        begin
          Thread.current[:dsl_item]  = item
          Thread.current[:dsl_array] = [item]
          Thread.current[:dsl_url]   = item
          Thread.current[:dsl_json]  = nil

          result = @dsl_binding.eval(sub(code, [item]))

          result.is_a?(Array) ? result : [result]
        ensure
          Thread.current[:dsl_item]  = prev_item
          Thread.current[:dsl_array] = prev_array
          Thread.current[:dsl_url]   = prev_url
          Thread.current[:dsl_json]  = prev_json
        end
      end
    end

    def execute_make_uri(code, arr)
      return [] if arr.blank?

      # parse params (simple version)
      params = parse_params(code)
      prefix = params['prefix'] || 'default'

      arr.map do |url|
        next if url.blank?

        id = extract_id_from_url(url)

        next if id.blank?

        "footlight:#{prefix}_#{id}"
      end.compact.uniq
    end

    def snapshot_thread_locals
      {
        dsl_array: fetch_thread_local(:dsl_array),
        dsl_url: fetch_thread_local(:dsl_url),
        dsl_json: fetch_thread_local(:dsl_json)
      }
    end

    def fetch_thread_local(key)
      Thread.current.key?(key) ? Thread.current[key] : :__dsl_missing
    end

    def restore_thread_locals(previous)
      restore_thread_local(:dsl_array, previous[:dsl_array])
      restore_thread_local(:dsl_url, previous[:dsl_url])
      restore_thread_local(:dsl_json, previous[:dsl_json])
    end

    def restore_thread_local(key, value)
      if value == :__dsl_missing
        # Thread#[] storage is cleared by assigning nil (Thread has no #delete).
        Thread.current[key] = nil if Thread.current.key?(key)
      else
        Thread.current[key] = value
      end
    end
    end
  end
end
