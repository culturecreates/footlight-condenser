require "stringio"
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
      @mode        = ctx[:mode] || @scrape_opts[:mode] || @scrape_opts["mode"]
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
      if export_debug?
        Rails.logger.warn(
          "[EXPORT_DEBUG] DSL.run entry url=#{@url} render_js=#{@render_js.inspect} steps=#{steps.size} " \
          "algorithm=#{algorithm.to_s[0, 240].inspect}"
        )
      end
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

          if export_debug?
            Rails.logger.warn(
              "[EXPORT_DEBUG] DSL.run abort step=#{step_index} type=#{prefix} url=#{@url} " \
              "error_type=#{out.last[:error_type] || out.last['error_type']}"
            )
          end
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

          if export_debug?
            Rails.logger.warn(
              "[EXPORT_DEBUG] DSL.run halt step=#{step_index} type=#{prefix} url=#{@url} results_count=#{Array(results).size}"
            )
          end
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

      if export_debug?
        Rails.logger.warn("[EXPORT_DEBUG] DSL.run exit url=#{@url} results_count=#{Array(results).size}")
      end
      results
    ensure
      restore_thread_locals(previous_locals)
    end

      private

    def export_debug?
      ENV["EXPORT_DEBUG"].present?
    end

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
          graph_status = ensure_graph!(step: 'sparql')
          return graph_status if abort_structure?(graph_status)

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

      fetch_result = fetch_result_for(url: @url, render_js: render_js, scrape_options: opts)
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

      fetch_result = fetch_result_for(url: @url, render_js: @render_js, scrape_options: @scrape_opts)
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

    def ensure_graph!(step: nil)
      return :ok if @graph

      fetch_result = fetch_result_for(url: @url, render_js: @render_js, scrape_options: @scrape_opts)
      @current_wringer_status =
        (fetch_result[:wringer] || {}).merge(
          duration_ms: fetch_result[:duration_ms]
        )
      raw = fetch_result[:body]

      if fetch_result[:status] == :abort
        return normalize_abort_result(raw, step: step)
      end

      @graph = load_rdf_graph(raw, fetch_result)
      :ok
    end

    def load_rdf_graph(body, fetch_result)
      source_url = fetch_result[:final_url].presence || @url
      headers = fetch_result[:headers] || {}
      content_type = headers[:content_type] || headers["content_type"] || headers[:"content-type"] || headers["Content-Type"]
      content_type = Array(content_type).first.to_s.presence
      text = body.to_s
      reader = RDF::Reader.for(content_type: content_type, file_name: source_url) { text[0, 1000] }
      raise RDF::FormatError, "unknown RDF format for #{source_url}" unless reader

      RDF::Graph.new do |graph|
        reader.new(StringIO.new(text), base_uri: source_url) do |rdf|
          graph << rdf
        end
      end
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

    def fetch_result_for(url:, render_js:, scrape_options:)
      options, log_context = sanitized_scrape_options(scrape_options)
      if use_wringer_compatibility_client?(options)
        wringer_client.fetch(url: url, render_js: render_js, scrape_options: options)
      else
        fetch_result_from_cache(url: url, render_js: render_js, scrape_options: options, log_context: log_context)
      end
    end

    def fetch_result_from_cache(url:, render_js:, scrape_options:, log_context:)
      website = scrape_options[:website] || scrape_options["website"]
      website_id = scrape_options[:website_id] || scrape_options["website_id"] || log_context[:website_id]
      fetch = Distillator::FetchCacheStore.fetch(
        uri: url,
        include_fragment: scrape_options.fetch(:include_fragment, true),
        force_scrape: scrape_options.fetch(:force_scrape, false),
        force_scrape_every_hrs: scrape_options[:force_scrape_every_hrs],
        render_js: render_js,
        mode: effective_distillator_mode(scrape_options),
        use_phantomjs: scrape_options.fetch(:use_phantomjs, false),
        absolute_src: scrape_options.fetch(:absolute_src, false),
        json_post: scrape_options.fetch(:json_post, false),
        website: website,
        website_id: website_id,
        agent: @agent,
        use_wringer: method(:use_wringer),
        safe_wringer_call: method(:safe_wringer_call),
        logger: Rails.logger,
        log_context: log_context
      )
      signals = (fetch.signals || {}).to_h.stringify_keys
      hints = Array(fetch.hints)
      body = fetch.body.presence || fetch.html
      if fetch.respond_to?(:content_success?) && !fetch.content_success?
        error_type = signals["blocking_issue_key"].presence || signals["primary_issue_key"].presence || "DistillatorContentFailure"
        error_message = "Fetch content blocked by #{error_type}"
        Rails.logger.warn(
          {
            event: "dsl.fetch.content_failure",
            url: url,
            error_type: error_type,
            final_url: fetch.final_url.presence || url,
            http_response_code: fetch.http_response_code,
            cache_hit: fetch.cache_hit,
            cache_write: fetch.cache_write,
            cache_reason: fetch.cache_reason,
            statement_id: log_context[:statement_id],
            source_id: log_context[:source_id],
            webpage_id: log_context[:webpage_id],
            website_id: log_context[:website_id]
          }
        )
        return {
          status: :abort,
          body: [
            "abort_update",
            {
              error: error_message,
              error_type: error_type,
              source: "distillator_fetch_cache",
              cache: fetch.respond_to?(:cache_policy) ? fetch.cache_policy : signals["cache"],
              retry: fetch.respond_to?(:retry_policy) ? fetch.retry_policy : signals["retry"],
              step: "url",
              signals: signals,
              hints: hints
            }
          ],
          headers: fetch.headers || {},
          final_url: fetch.final_url.presence || url,
          redirect_chain: fetch.redirect_chain || [],
          wringer: {
            error_type: error_type,
            source: "distillator_fetch_cache",
            cache: fetch.respond_to?(:cache_policy) ? fetch.cache_policy : signals["cache"],
            retry: fetch.respond_to?(:retry_policy) ? fetch.retry_policy : signals["retry"],
            signals: signals,
            hints: hints,
            final_url: fetch.final_url.presence || url,
            redirect_chain: fetch.redirect_chain || [],
            fetch_path: fetch.fetch_path,
            cache_hit: fetch.cache_hit,
            cache_write: fetch.cache_write,
            cache_reason: fetch.cache_reason,
            uri_key: fetch.uri_key,
            normalized_url: fetch.normalized_url
          },
          duration_ms: fetch.duration_ms,
          http_code: fetch.http_response_code,
          raw_body: body
        }
      end
      abort_payload =
        if body.is_a?(Array) && body.first == "abort_update" && body.second.is_a?(Hash)
          body.second.with_indifferent_access
        end

      if abort_payload.present? || (body.blank? && signals["error_type"].present?)
        error_type = abort_payload&.[](:error_type).presence || signals["error_type"]
        error_message = abort_payload&.[](:error).presence || hints.first.presence || "Fetch cache returned no content"
        return {
          status: fetch.status,
          body: if abort_payload.present?
  body
                else
  [
    "abort_update",
    {
      error: error_message,
      error_type: error_type,
      source: "distillator_fetch_cache",
      cache: true,
      step: "url"
    }
  ]
                end,
          headers: fetch.headers || {},
          final_url: fetch.final_url.presence || url,
          redirect_chain: fetch.redirect_chain || [],
          wringer: {
            error_type: error_type,
            source: abort_payload&.[](:source).presence || "distillator_fetch_cache",
            cache: abort_payload&.key?(:cache) ? abort_payload[:cache] : true,
            retry: abort_payload&.[](:retry),
            signals: signals,
            hints: hints,
            final_url: fetch.final_url.presence || url,
            redirect_chain: fetch.redirect_chain || [],
            fetch_path: fetch.fetch_path,
            cache_hit: fetch.cache_hit,
            cache_write: fetch.cache_write,
            cache_reason: fetch.cache_reason,
            uri_key: fetch.uri_key,
            normalized_url: fetch.normalized_url
          },
          duration_ms: fetch.duration_ms,
          http_code: fetch.http_response_code,
          raw_body: body
        }
      end

      {
        status: fetch.status,
        body: body,
        headers: fetch.headers || {},
        final_url: fetch.final_url.presence || url,
        redirect_chain: fetch.redirect_chain || [],
        wringer: {
          cache: true,
          signals: signals,
          hints: hints,
          final_url: fetch.final_url.presence || url,
          redirect_chain: fetch.redirect_chain || [],
          http_response_code: fetch.http_response_code,
          fetch_path: fetch.fetch_path,
          cache_hit: fetch.cache_hit,
          cache_write: fetch.cache_write,
          cache_reason: fetch.cache_reason,
          uri_key: fetch.uri_key,
          normalized_url: fetch.normalized_url
        },
        duration_ms: fetch.duration_ms,
        http_code: fetch.http_response_code,
        raw_body: body
      }
    end

    def sanitized_scrape_options(scrape_options)
      return [{}, {}] unless scrape_options.respond_to?(:deep_dup)

      website = scrape_options[:website] || scrape_options["website"]
      options = scrape_options.deep_dup.with_indifferent_access
      log_context = options.delete(:log_context) || options.delete("log_context") || {}
      normalized_options = options.to_h.symbolize_keys
      normalized_options[:website] = website if website
      [normalized_options, log_context.to_h.symbolize_keys]
    end

    def use_wringer_compatibility_client?(scrape_options)
      options = scrape_options.respond_to?(:symbolize_keys) ? scrape_options.symbolize_keys : {}
      Distillator::BooleanParam.parse(options[:wringer_compatibility] || options["wringer_compatibility"]) == true
    end

    def truthy?(value)
      value == true || value.to_s == "true"
    end

    def effective_distillator_mode(scrape_options)
      explicit =
        scrape_options[:mode] ||
        scrape_options["mode"] ||
        @mode

      return nil if explicit.blank?
      normalized = explicit.to_s.strip.downcase
      normalized = Distillator::FetchMode::ALIASES.fetch(normalized, normalized)
      return nil unless Distillator::FetchMode::EXECUTION_MODES.include?(normalized)

      normalized.to_sym
    end

    def use_wringer(u, rj, opt)
      ApplicationController.helpers.use_wringer(u, rj, opt)
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
