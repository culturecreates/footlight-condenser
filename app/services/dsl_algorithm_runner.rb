class DslAlgorithmRunner
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

    # reset thread-local DSL state for this run
    Thread.current[:dsl_array] = []
    Thread.current[:dsl_url]   = @url
    Thread.current[:dsl_json]  = nil

    @dsl_binding = binding

    steps = algorithm.split(';')

    steps.each_with_index do |raw, idx|
      prefix, code = raw.partition('=').values_at(0, 2)
      step_index  = idx + 1

      input_copy  = Marshal.load(Marshal.dump(results))
      url_before  = @url
      start_time  = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      out = execute(prefix, code, results)

      end_time    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      duration_ms = ((end_time - start_time) * 1000).round(1)

      url_after   = @url
      output      = Array(out)

      @tracer.step(
        step: step_index,
        type: prefix,
        code: code,
        input: input_copy,
        output: output,
        error: nil,
        url_before: url_before,
        url_after: url_after,
        duration_ms: duration_ms
      )

      results = output
    rescue StandardError => e
      @tracer.step(
        step: step_index,
        type: prefix,
        code: code,
        input: input_copy,
        output: [],
        error: e,
        url_before: url_before,
        url_after: @url,
        duration_ms: duration_ms
      )
      return ["abort_update", { error: e.message, error_type: e.class.to_s }]
    end

    results
  end

  private

  def execute(prefix, code, arr)
    case prefix

    when 'sparql'
      @graph ||= RDF::Graph.load(use_wringer(@url, @render_js, @scrape_opts))
      sparql = "PREFIX schema: <http://schema.org/> select * where " + code
      rows = SPARQL.execute(sparql, @graph)

      if rows.count == 1
        [rows.first.answer.value]
      else
        rows.map { |r| r.answer.value }
      end

    when 'url'
      new_url = @dsl_binding.eval(sub(code, arr))
      @url = new_url

      raw = safe_wringer_call { @agent.get_file(use_wringer(@url, @render_js, @scrape_opts)) }
      return raw if abort_structure?(raw)

      @html = raw
      @page = Nokogiri::HTML(@html, nil, Encoding::UTF_8.to_s)
      arr

    when 'renderjs_url'
      new_url = @dsl_binding.eval(sub(code, arr))
      @url = new_url

      raw = safe_wringer_call { @agent.get_file(use_wringer(@url, true, @scrape_opts)) }
      return raw if abort_structure?(raw)

      @html = raw
      @page = Nokogiri::HTML(@html, nil, Encoding::UTF_8.to_s)
      arr

    when 'json_url'
      new_url = @dsl_binding.eval(sub(code, arr))
      @url = new_url

      raw = safe_wringer_call { @agent.get_file(use_wringer(@url, @render_js, @scrape_opts)) }
      return raw if abort_structure?(raw)

      @html = raw
      Struct.new(:text).new(@html)

    when 'post_url'
      new_url = @dsl_binding.eval(sub(code, arr))
      @url = new_url

      temp_opts = @scrape_opts.merge(json_post: true).merge(force_scrape_every_hrs: 1)
      data = @agent.get_file(use_wringer(@url, @render_js, temp_opts))
      @page = Nokogiri::HTML(data, nil, Encoding::UTF_8.to_s)
      arr

    when 'api'
      new_url = @dsl_binding.eval(sub(code, arr))
      data = HTTParty.get(new_url)
      raise "API error #{data.code}" unless data.code.to_s.start_with?('2')

      JSON.parse(data.body)

    when 'xpath'
      ensure_page!
      @page.xpath(code).map(&:text)

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
      return :__dsl_break__ if nodes.blank?

      nodes.map(&:text)

    when 'unless_xpath'
      ensure_page!
      nodes = @page.xpath(code)
      return :__dsl_break__ if nodes.present?

      arr

    when 'css'
      ensure_page!
      @page.css(code).map(&:text)

    when 'json'
      ensure_page!
      @json ||= JSON.parse(@page.text)
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
      updated_arr = Thread.current[:dsl_array]
      @url  = Thread.current[:dsl_url]
      @json = Thread.current[:dsl_json]

      updated_arr || result

    else
      raise "Missing DSL prefix: #{prefix}=#{code}"
    end
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

    raw = safe_wringer_call { @agent.get_file(use_wringer(@url, @render_js, @scrape_opts)) }
    if abort_structure?(raw)
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

  def sanitize(*args)
    ApplicationController.helpers.sanitize(*args)
  end
end