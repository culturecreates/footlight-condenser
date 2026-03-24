# app/services/dsl/dsl_algorithm_runner.rb
module Dsl
  class DslAlgorithmRunner
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
        return ["abort_update", { error: e.message, error_type: e.class.to_s }]
      end

      results
    ensure
      restore_thread_locals(previous_locals)
    end

    private

    def ok(v)    = [:ok, v].freeze
    def skip     = [:skip, nil].freeze
    def abort(v) = [:abort, v].freeze

    def execute(prefix, code, arr)
      case prefix

      when 'sparql'
        begin
          @graph ||= RDF::Graph.load(use_wringer(@url, @render_js, @scrape_opts))
          sparql = "PREFIX schema: <http://schema.org/> select * where #{code}"
          rows = SPARQL.execute(sparql, @graph)
          [*(rows.count == 1 ? rows.first.answer.value : rows.map { |r| r.answer.value })]
        rescue StandardError => e
          ["abort_update", { error: e.message, error_type: e.class.to_s }]
        end

      when 'url'           then handle_url_step(code, arr)

      when 'renderjs_url'  then handle_url_step(code, arr, render_js: true)

      when 'post_url'
        temp_opts = @scrape_opts.merge(json_post: true).merge(force_scrape_every_hrs: 1)
        handle_url_step(code, arr, opts: temp_opts)

      when 'json_url'
        status, result = resolve_and_fetch_url(code, arr)

        return result if status == :abort
        return arr if status == :skip

        apply_json_text_result(result)

        arr

      when 'api'
        new_url = resolve_url_only(code, arr)
        return arr unless new_url

        data = HTTParty.get(new_url)
        raise "API error #{data.code}" unless data.code.to_s.start_with?('2')

        JSON.parse(data.body)

      when 'xpath'
        execute_xpath(code)

      when 'xpath_sanitize'
        ensure_page!
        @page.xpath(code).map do |node|
          sanitize(node.to_s,
                   tags: %w[h1 h2 h3 h4 h5 h6 p li ul ol strong em a i br],
                   attributes: %w[href])
        end

      when 'if_xpath'
        ensure_page!
        nodes = @page.xpath(code)
        return [HALT, arr] if nodes.blank?

        nodes.map(&:text)

      when 'unless_xpath'
        ensure_page!
        nodes = @page.xpath(code)
        return [HALT, arr] if nodes.present?

        arr

      when 'css'
        ensure_page!
        @page.css(code).map(&:text)

      when 'json'
        ensure_page!
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

      probe_output = Array(execute_xpath("//title")).compact.map(&:to_s).first(3)
      @probed_url_step_indices << previous_step_index

      {
        status: "ok",
        xpath: "//title",
        output: probe_output
      }
    rescue StandardError
      @probed_url_step_indices << previous_step_index if previous_step_index

      {
        status: "ok",
        xpath: "//title",
        output: []
      }
    end

    def resolve_and_fetch_url(code, arr, render_js: @render_js, opts: @scrape_opts)
      raw = @dsl_binding.eval(sub(code, arr))
      new_url = Dsl::UrlResolver.extract(raw)
      if new_url.blank?
        Rails.logger.debug { "[DSL] skipped invalid URL from #{raw.inspect}" }
        return skip 
      end

      Rails.logger.debug { "[DSL] #{code} → #{new_url}" }

      @url = new_url

      fetch_result = wringer_client.fetch(url: @url, render_js: render_js, scrape_options: opts)
      @current_wringer_status = fetch_result[:wringer]
      raw = fetch_result[:body]

      if fetch_result[:status] == :abort
        Rails.logger.warn("[DSL] abort on #{new_url} (#{@current_wringer_status&.dig(:error_type)})")
        return abort(raw)
      end

      ok(raw)
    end

    def resolve_url_only(code, arr)
      Dsl::UrlResolver.extract(@dsl_binding.eval(sub(code, arr)))
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

    def handle_url_step(code, arr, render_js: false, opts: @scrape_opts)
      status, result = resolve_and_fetch_url(code, arr, render_js: render_js, opts: opts)

      return result if status == :abort
      return arr    if status == :skip

      apply_html_result(result)
      arr
    end

    def execute_xpath(code)
      ensure_page!
      @page.xpath(code).map(&:text)
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
    end

    def ensure_page!
      return if @page

      fetch_result = wringer_client.fetch(url: @url, render_js: @render_js, scrape_options: @scrape_opts)
      @current_wringer_status = fetch_result[:wringer]
      raw = fetch_result[:body]

      if fetch_result[:status] == :abort
        raise StandardError, raw.last[:error]
      end

      @html = raw
      @page = Nokogiri::HTML(@html, nil, Encoding::UTF_8.to_s)
    end

    def use_wringer(u, rj, opt)
      ApplicationController.helpers.use_wringer(u, rj, opt)
    end

    def safe_wringer_call(&blk)
      ApplicationController.helpers.safe_wringer_call(&blk)
    end

    def wringer_client
      @wringer_client ||= Dsl::WringerClient.new(
        agent: @agent,
        render_js: @render_js,
        scrape_options: @scrape_opts,
        use_wringer: method(:use_wringer),
        safe_wringer_call: method(:safe_wringer_call),
        logger: Rails.logger
      )
    end

    def sanitize(*args)
      ApplicationController.helpers.sanitize(*args)
    end

    def trace_preview(value)
      value.is_a?(Array) ? value : [value]
    end

    def trace_wringer_payload
      return @current_wringer_status if @current_wringer_status.present?

      { inherited: true }
    end

    def trace_probe_payload(probe_result)
      return { skipped: true } unless probe_result.present?

      {
        result: probe_result,
        ok: probe_result[:status].to_s == "ok"
      }
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
