class DslAlgorithmRunner
  StepTrace = Struct.new(
    :step,
    :type,
    :code,
    :input,
    :output,
    :error,
    keyword_init: true
  )

  def initialize(ctx)
    @url          = ctx[:url]
    @render_js    = ctx[:render_js]
    @scrape_opts  = ctx[:scrape_options] || {}
    @tracer       = ctx[:tracer]
    @agent        = Mechanize.new
    @agent.user_agent_alias = 'Mac Safari'
    @html         = nil
    @page         = nil
    @json         = nil
    @graph        = nil
  end

  def abort_structure?(obj)
    obj.is_a?(Array) &&
      obj.length == 2 &&
      obj.first == "abort_update" &&
      obj.last.is_a?(Hash)
  end

  def run(algorithm)
    results = []

    # Manual override
    if algorithm.to_s.start_with?('manual=')
      r = [algorithm.delete_prefix('manual=')]
      @tracer.step(step: 1, type: 'manual', code: algorithm, input: [], output: r, error: nil)
      return r
    end

    steps = algorithm.split(';')
    steps.each_with_index do |raw, idx|
      prefix, code = raw.partition('=').values_at(0,2)
      step_index = idx + 1
      input_copy = Marshal.load(Marshal.dump(results))

      begin
        out = execute(prefix, code, results)

        # If execute returned a wringer-style abort hash, convert it
        if out.is_a?(Hash) && out[:abort_update]
          # Make a proper DSL abort message
          error_info = out[:error]
          @tracer.step(
            step: step_index,
            type: prefix,
            code: code,
            input: input_copy,
            output: [],
            error: error_info
          )
          return ["abort_update", { error: error_info, error_type: "WringerError" }]
        end

        # If a DSL break signal
        break if out == :__dsl_break__

        # If our own DSL abort format
        if abort_structure?(out)
          @tracer.step(
            step: step_index,
            type: prefix,
            code: code,
            input: input_copy,
            output: out,
            error: out[1][:error]
          )
          return out
        end

        # Normal result
        results = Array(out)
        @tracer.step(
          step: step_index,
          type: prefix,
          code: code,
          input: input_copy,
          output: results,
          error: nil
        )
      rescue StandardError => e
        @tracer.step(
          step: step_index,
          type: prefix,
          code: code,
          input: input_copy,
          output: [],
          error: "#{e.class}: #{e.message}"
        )

        return ["abort_update", { error: e.message.to_s, error_type: e.class.to_s }]
      end
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
      new_url = eval(sub(code, arr))
      @url = new_url
      # @html = safe_wringer_call { @agent.get_file(use_wringer(@url, @render_js, @scrape_opts)) }
      # @page = Nokogiri::HTML(@html, nil, Encoding::UTF_8.to_s)
      raw = safe_wringer_call { @agent.get_file(use_wringer(@url, @render_js, @scrape_opts)) }
      if raw.is_a?(Array) && raw.first == "abort_update"
        return raw        # short-circuit abort
      end

      @html = raw
      @page = Nokogiri::HTML(@html, nil, Encoding::UTF_8.to_s)
      arr

    when 'renderjs_url'
      new_url = eval(sub(code, arr))
      @url = new_url
      # @html = safe_wringer_call { @agent.get_file(use_wringer(@url, true, @scrape_opts)) }
      # @page = Nokogiri::HTML(@html, nil, Encoding::UTF_8.to_s)
      raw = safe_wringer_call { @agent.get_file(use_wringer(@url, @render_js, @scrape_opts)) }
      if raw.is_a?(Array) && raw.first == "abort_update"
        return raw        # short-circuit abort
      end

      @html = raw
      @page = Nokogiri::HTML(@html, nil, Encoding::UTF_8.to_s)
      arr

    when 'json_url'
      new_url = eval(sub(code, arr))
      @url = new_url
      # @html = safe_wringer_call { @agent.get_file(use_wringer(@url, @render_js, @scrape_opts)) }
      raw = safe_wringer_call { @agent.get_file(use_wringer(@url, @render_js, @scrape_opts)) }
      if raw.is_a?(Array) && raw.first == "abort_update"
        return raw        # short-circuit abort
      end
      
      @html = raw
      Struct.new(:text).new(@html)

    when 'post_url'
      new_url = eval(sub(code, arr))
      @url = new_url
      temp_opts = @scrape_opts.merge(json_post: true).merge(force_scrape_every_hrs: 1)
      data = @agent.get_file(use_wringer(@url, @render_js, temp_opts))
      @page = Nokogiri::HTML(data, nil, Encoding::UTF_8.to_s)
      arr

    when 'api'
      new_url = eval(sub(code, arr))
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
      eval(code.gsub('$json', '@json'))

    when 'time_zone'
      ["time_zone: #{code}"]

    when 'ruby'
      eval(sub(code, arr))

    else
      raise "Missing DSL prefix: #{prefix}=#{code}"
    end
  end

  def sub(code, arr)
    code.to_s.gsub('$array','arr').gsub('$url','@url').gsub('$json','@json')
  end

  # def ensure_page!
  #   return if @page

  #   @html ||= safe_wringer_call { @agent.get_file(use_wringer(@url, @render_js, @scrape_opts)) }
  #   @page ||= Nokogiri::HTML(@html, nil, Encoding::UTF_8.to_s)
  # end
  # 
  def ensure_page!
    return if @page

    raw = safe_wringer_call { @agent.get_file(use_wringer(@url, @render_js, @scrape_opts)) }
    if raw.is_a?(Array) && raw.first == "abort_update"
      # propagate abort up to runner
      raise StandardError, raw.last[:error] 
    end

    @html = raw
    @page = Nokogiri::HTML(@html, nil, Encoding::UTF_8.to_s)
  end

  def use_wringer(u,rj,opt) = ApplicationController.helpers.use_wringer(u, rj, opt)
  def safe_wringer_call(&blk) = ApplicationController.helpers.safe_wringer_call(&blk)
  def sanitize(*args) = ApplicationController.helpers.sanitize(*args)
end
