# frozen_string_literal: true

module StatementsHelper
  include ApplicationHelper
  include CcKgHelper
  include CcWringerHelper
  Page = Struct.new(:text) # Used to simulate Nokogiri object's text method

  def self.build_refresh_proxy(cookies: {})
    helper = Object.new
    helper.extend(StatementsHelper)
    helper.instance_variable_set(:@_statement_refresh_cookies, cookies.with_indifferent_access)
    helper.define_singleton_method(:cookies) { @_statement_refresh_cookies }
    helper
  end

# :nocov:
  def process_algorithm_with_trace(algorithm:, render_js: false, language: "en", url:, scrape_options: {})
    collector = Dsl::Tracing::TraceCollector.new
    ctx = {
      url: url,
      render_js: render_js,
      scrape_options: scrape_options,
      tracer: collector
    }
    result = Dsl::Core::AlgorithmRunner.new(ctx).run(algorithm)
    [result, collector.to_h]
  end

  def trace_truncated_tooltip(str, length: nil, tooltip_length: nil)
    safe_str = str.is_a?(String) ? str : str.inspect

    # Parse cookie values into integers
    display_len =
      if length.present?
        length.to_i
      elsif cookies[:trace_code_display_length].present?
        cookies[:trace_code_display_length].to_i
      else
        180
      end

    tooltip_len =
      if tooltip_length.present?
        tooltip_length.to_i
      elsif cookies[:trace_code_tooltip_length].present?
        cookies[:trace_code_tooltip_length].to_i
      end

    # Fallback: if cookie says “0” then nil out
    tooltip_len = nil if tooltip_len == 0

    # Now safe comparison
    truncated =
      if safe_str.length > display_len
        "#{safe_str[0, display_len]}…"
      else
        safe_str
      end

    # Truncate tooltip text if needed
    tool_text =
      if tooltip_len && safe_str.length > tooltip_len
        "#{safe_str[0, tooltip_len]}…"
      else
        safe_str
      end

    content_tag(
      :span,
      truncated,
      class: "trace-tooltip",
      data: { tooltip: tool_text }
    )
  end
# :nocov:
 
  def truncate_for_flash(x, max: 500)
    s = x.is_a?(String) ? x : x.inspect
    s.length > max ? "#{s[0, max]}…(truncated)" : s
  end

  def preview(value, limit = 200)
    str = value.inspect
    str.length > limit ? "#{str[0, limit]}..." : str
  rescue StandardError
    value.to_s
  end

  def split_algorithm_steps(algorithm)
    return [] if algorithm.blank?

    algorithm
      .split(";")
      .map(&:strip)
      .reject(&:blank?)
  end

  def trace_display_output(step)
    current = normalize_step_hash(step)
    output = current.key?(:output_full) ? current[:output_full] : current[:output]
    output = current[:input] if output.nil?

    if trace_presenter.semantic_label(current) == "Navigation"
      current[:url_after].presence || (output.is_a?(Array) ? output.last : output)
    else
      output
    end
  end

  def cache_freshness_label(statement)
    return nil unless statement.cache_refreshed.present?

    age_seconds = Time.current - statement.cache_refreshed

    case age_seconds
    when 0..3600
      "fresh"
    when 3600..86_400
      "#{(age_seconds / 3600).to_i}h ago"
    when 86_400..7 * 86_400
      "#{(age_seconds / 86_400).to_i}d ago"
    when 7*86_400..14*86_400
      "#{(age_seconds / (7*86_400)).to_i}w ago"
    when 14*86_400..30*86_400
      "2–4w ago"
    else
      "stale"
    end
  end

  def wringer_links_for_step(step = nil, website: nil, website_id: nil, **step_kwargs)
    current = normalize_step_hash(step.presence || step_kwargs)
    wringer = current[:wringer].is_a?(Hash) ? current[:wringer].with_indifferent_access : {}
    return nil if wringer.blank?

    url = current[:url_after].presence || current[:url_before]
    return nil if url.blank?

    encoded = CGI.escape(CGI.escape(url))
    base = get_wringer_url_per_environment

    {
      wringer_search: "#{base}/websites?term=#{encoded}",
      raw_url: url,
      active_cache: Distillator::CacheLinkResolver.call(
        url: url,
        website: website,
        website_id: website_id || current[:website_id]
      )
    }
  end

  def interactive_redirect_info(step)
    current = normalize_step_hash(step)
    wringer = current[:wringer]
    wringer = wringer.is_a?(Hash) ? wringer.with_indifferent_access : {}
    return nil if wringer.blank?

    final_url =
      wringer[:final_url] ||
      wringer.dig(:signals, :final_url)

    base_url = current[:url_after] || current[:url_before]
    redirect_chain_present = wringer[:redirect_chain].present?
    redirected = redirect_chain_present || (final_url.present? && base_url.present? && final_url.to_s != base_url.to_s)
    return nil unless redirected

    info = "Network: redirected"
    info += " -> #{final_url}" if final_url.present?
    info
  end

  def wringer_network_metadata(step)
    interactive_redirect_info(step)
  end

  def statement_cache_links(statement)
    Distillator::CacheLinkResolver.call(url: statement.webpage.url, website: statement.webpage.website)
  end

  def statement_rollout_badge(statement)
    operator_rollout_badge(statement.webpage.website)
  end

  def statement_rollout_explanation(statement)
    operator_rollout_explanation(statement.webpage.website)
  end

  def normalize_step_hash(step)
    step.is_a?(Hash) ? step.with_indifferent_access : {}
  end

  # Refreshes a statement by executing its DSL algorithm.
  #
  # @param stat [Statement]  The statement object to refresh.
  # @param scrape_options [Hash]  Optional scraping options (e.g., { force_scrape_every_hrs: 24 }).
  #
  # This method:
  #  * Prevents refresh of manual statements when they are already marked OK/updated.
  #  * Detects whether DSL trace is enabled via cookies[:dsl_trace].
  #  * Calls `run_dsl` with the correct parameters to execute the algorithm.
  #  * Normalizes trace data when trace is enabled (`@dsl_trace` is set).
  #  * Handles abort signals (`["abort_update", {...}]`) returned by the DSL.
  #  * Validates results and populates ActiveModel errors on failure.
  #  * Formats and saves the new statement cache when appropriate.
  #
  # If trace is enabled, `run_dsl` returns [result, trace_array], where each trace
  # element is a Hash containing:
  #   :step          — step index
  #   :type          — DSL prefix (e.g., xpath, ruby)
  #   :code          — the DSL code executed
  #   :input_preview — preview of input before the step
  #   :output_preview— preview of output after the step
  #   :url_before    — URL before step
  #   :url_after     — URL after step
  #   :duration_ms   — step execution time in milliseconds
  #   :error_class   — class name of error (if any)
  #   :error_message — error message (if any)
  #
  # The trace array is assigned to @dsl_trace for view rendering.
  #
  # **Exceptions:** Does not raise; adds errors on the `stat` object instead.
  def refresh_statement_helper(stat, scrape_options = {})
    @dsl_trace = nil
    data = nil
    error_messages = []
    build_result = lambda do
      {
        data: data,
        trace: @dsl_trace,
        errors: (error_messages + stat.errors.full_messages).compact.uniq
      }
    end

    # Disallow refresh if manual and already OK/updated
    if stat.manual && %w[ok updated].include?(stat.status)
      message = "No update unless status is 'initial', 'problem', or 'missing'."
      stat.errors.add(:base, message)
      error_messages << message
      return build_result.call
    end

    # Detect trace mode via cookie
    trace_enabled = trace_enabled_for_request?
    abort_error_message = nil

    dsl_result = run_dsl(
      algorithm: stat.source.algorithm_value,
      render_js: stat.source.render_js,
      language: stat.source.language,
      url: stat.webpage.url,
      scrape_options: statement_refresh_scrape_options(stat, scrape_options),
      trace: trace_enabled
    )

    if trace_enabled
      if dsl_result.is_a?(Array) && dsl_result.size == 2
        data, trace = dsl_result
        @dsl_trace = trace
      else
        # Defensive fallback
        data = dsl_result
        @dsl_trace = []

        Rails.logger.warn do
          "[DSL TRACE WARNING] Unexpected run_dsl return shape: #{dsl_result.class}"
        end
      end
    else
      data = dsl_result
    end

    # Check for abort_update signal
    if data.is_a?(Array) && data.first == "abort_update"
      info = data.second || {}
      abort_error_message = compact_refresh_error(info)
      stat.errors.add(:base, abort_error_message)
      error_messages << abort_error_message
      return build_result.call
    end

    # Blank result is not valid for existing statements
    if data.blank? && !stat.new_record?
      message = "DSL returned blank result (possible parsing failure)"
      stat.errors.add(:base, message)
      error_messages << message

      # Also attach context for debugging
      Rails.logger.warn do
        "[DSL BLANK RESULT] statement_id=#{stat.id} url=#{stat.webpage.url}"
      end

      return build_result.call
    end

    # Format the result according to the property's datatype
    formatted = format_datatype(data, stat.source.property, stat.webpage)

    # Save if appropriate
    if save_record?(formatted.to_s, stat.status, stat.cache, stat.new_record?)
      # Preserve manual links for xsd:anyURI
      if stat.source.property.value_datatype == 'xsd:anyURI'
        formatted = preserve_manual_links(formatted, stat.cache)
      end

      stat.cache           = formatted
      stat.cache_refreshed = Time.zone.now
      stat.save
    end

    # ActiveRecord save can clear in-memory errors; keep explicit abort context for callers/tests.
    if abort_error_message.present? && stat.errors.empty?
      stat.errors.add(:base, abort_error_message)
      error_messages << abort_error_message
    end

    build_result.call
  end

  def compact_refresh_error(error)
    payload =
      if error.is_a?(Hash)
        error
      elsif !error.is_a?(Array) && error.respond_to?(:to_h)
        error.to_h
      else
        {}
      end

    payload = payload.with_indifferent_access if payload.respond_to?(:with_indifferent_access)
    error_type = payload[:error_type].presence || "RefreshError"
    step = payload[:step].presence
    signals = payload[:signals].respond_to?(:to_h) ? payload[:signals].to_h.with_indifferent_access : {}
    issue = signals[:blocking_issue_key].presence || signals[:primary_issue_key].presence || payload[:error_type]
    message = payload[:error].to_s
    message = message.tr("\n", " ").squish
    message = message[0, 180] + "..." if message.length > 180

    parts = ["Scrape aborted (#{error_type})"]
    parts << "step=#{step}" if step.present?
    parts << "issue=#{issue}" if issue.present? && issue.to_s != error_type.to_s
    parts << message if message.present?
    parts.join(": ")
  end

  def compact_refresh_errors(errors)
    Array(errors).map { |error| compact_refresh_error(error) }
  end

  def trace_enabled_for_request?
    return false unless respond_to?(:cookies)

    cookie_jar = cookies
    return false unless cookie_jar.respond_to?(:[])

    value = cookie_jar[:dsl_trace]
    value = value[:value] if value.is_a?(Hash)
    value.to_s == "true"
  end

  def statement_refresh_scrape_options(stat, scrape_options)
    options =
      if scrape_options.respond_to?(:to_h)
        scrape_options.to_h.symbolize_keys
      else
        {}
      end

    options.reverse_merge(
      json_post: stat.source.json_post?,
      use_phantomjs: stat.source.render_js,
      website: stat.source.website,
      website_id: stat.source.website_id
    ).merge(
      log_context: {
        statement_id: stat.id,
        source_id: stat.source_id,
        webpage_id: stat.webpage_id,
        website_id: stat.webpage&.website_id || stat.source.website_id
      }
    )
  end


  ## Core logic of when to update records
  ## but safeguard against blank data and errors
  ## from unreliable internet sources
  def save_record?(data_str,stat_status,stat_cache, new_record)
    if data_str&.include?('abort_update')
      if ['initial','problem','missing'].include?(stat_status)
        true
      elsif stat_cache&.include?('abort_update')  # update cache with new error
        true
      else # preseve cache when status is ok or updated
        false
      end
    elsif data_str.blank? # blank and not an abort_update
      if new_record
        true
      elsif stat_cache&.include?('abort_update')
        true # replace previous abort_update with blank
      else
        false 
      end
    else
      true
    end
  end

  def run_dsl(
    algorithm:,
    render_js: false,
    language: "en",
    url:,
    scrape_options: {},
    trace: false,
    trace_opts: {}
  )
    Rails.logger.debug ">>> run_dsl invoked; trace_enabled=#{trace.inspect}"
    Rails.logger.debug ">>> algorithm: #{algorithm.inspect}"
    Rails.logger.debug ">>> start url: #{url.inspect}"

    tracer = trace ? Dsl::Tracing::TraceCollector.new(**trace_opts) : Dsl::Tracing::NullTracer.new

    ctx = {
      url: url,
      render_js: render_js,
      scrape_options: scrape_options,
      tracer: tracer
    }

    result = Dsl::Core::AlgorithmRunner.new(ctx).run(algorithm)

    # If not tracing, just return the result
    unless trace
      Rails.logger.debug ">>> run_dsl (no trace) returning: #{result.inspect}"
      return result
    end

    # ### TRACE IS ENABLED ###
    raw_events = tracer.to_h
    Rails.logger.debug ">>> tracer.to_h returned array: #{raw_events.inspect}"

    normalized_events = Dsl::Tracing::TraceFormatter.normalize(raw_events)

    Rails.logger.debug ">>> normalized_events: #{normalized_events.inspect}"

    [result, normalized_events]
  end

  ##
  # Process alorithm for a statement
  # INPUTS
  #   statement.source.algorithm
  #   statement.source.render_js
  #   statement.webpage.language - language of website set in condenser, not source language which is optional
  #   statement.webpage.url
  #   scrape_options - passed on to footlight-wringer scraping service. 
  #   statement.cache_refreshed - cache refreshed, lastCrawledAt, schema:lastReview
  #   statement.cache_changed - cache changed, date modified, schema:sdDatePublished
  # OUTPUT
  #   [results] array
  #   Algorithms that generate an error (i.e. ruby syntax) return ["abort_update", {error: e.inspect, results_prior: results_list, algorithm_rescued: a}
  # def process_algorithm(algorithm:, render_js: false, language: "en", url:, scrape_options: {}) #, cache_refreshed:, cache_changed:)
  #   if algorithm.start_with?('manual=')
  #     results_list = [algorithm.delete_prefix('manual=')]
  #   else
  #     agent = Mechanize.new
  #     agent.user_agent_alias = 'Mac Safari'
  #     html = nil
  #     page = nil
  #     json_scraped = nil # needed for case with ruby using $json in eval with 'json_scraped' scope
  #     results_list = []
  #     substitue_vars = lambda { |s| s.gsub('$array', 'results_list').gsub('$url', 'url').gsub('$json', 'json_scraped')}
  #     algorithm.split(";").each do |a|
  #       algo_type = a.partition('=').first
  #       algo = a.partition('=').last
  #       begin
  #         case algo_type 
  #         when "sparql"
  #           graph ||= RDF::Graph.load(use_wringer(url, render_js, scrape_options)) 
  #           sparql = "PREFIX schema: <http://schema.org/> select * where " + algo
  #           results = SPARQL.execute(sparql,graph)

  #           results_list << if results.count == 1
  #                           results.first.answer.value
  #                         else
  #                           results.map {|result| result.answer.value}
  #                         end
  #           results_list.flatten!
  #         when "url"
  #           # replace current page by scraping new url
  #           # using format url='http://example.com' or ruby like url=$url + '.json'
  #           new_url = eval(substitue_vars.call(algo))
  #           logger.info "*** New URL formed: #{new_url}"
  #           html = safe_wringer_call { agent.get_file(use_wringer(new_url, render_js, scrape_options)) }
  #           page = Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
  #         when 'renderjs_url'
  #           # FORCE Render JS -- replace current page by scraping new url with wringer
  #           # using format renderjs_url='http://example.com'
  #           new_url =  eval(substitue_vars.call(algo))
  #           logger.info "*** New URL formed: #{new_url}"
  #           html = safe_wringer_call { agent.get_file(use_wringer(new_url, true, scrape_options)) }
  #           page = Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
  #         when 'json_url'
  #           new_url =  eval(substitue_vars.call(algo))
  #           logger.info "*** New URL for JSON call: #{new_url}"
  #           html = safe_wringer_call { agent.get_file(use_wringer(new_url, render_js, scrape_options)) }
  #           page = Page.new(html)  # Do not use Nokogiri because it will remove html TODO: move struct down here
  #         when 'post_url'
  #           # replace current page data by scraping new url with wringer using POST
  #           # using format url='http://example.com?param_for_post='
  #           new_url =  eval(substitue_vars.call(algo))
  #           logger.info "*** New POST URL formed: #{new_url}"
  #           temp_scrape_options = scrape_options.merge(json_post: true).merge(force_scrape_every_hrs: 1)
  #           data = agent.get_file use_wringer(new_url, render_js, temp_scrape_options)
  #           page = Nokogiri::HTML(data, nil, Encoding::UTF_8.to_s)
  #         when 'api' # ok
  #           # Call API without going through wringer
  #           new_url =  eval(substitue_vars.call(algo))
  #           logger.info "*** New json api URL formed: #{new_url}"
  #           data = HTTParty.get(new_url)
  #           logger.info "*** api response body: #{data.body}"
  #           results_list = JSON.parse(data.body)
  #         when 'ruby' # test
  #           # Use ruby to process a var
  #           # ruby=$array.map{} or ruby=$json['name']
  #           results_list = eval(substitue_vars.call(algo))
  #         when 'xpath_sanitize' # ok
  #           html ||= safe_wringer_call { agent.get_file(use_wringer(url, render_js, scrape_options)) }
  #           page ||= Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
  #           page_data = page.xpath(algo)
  #           page_data.each { |d| results_list << sanitize(d.to_s, tags: %w[h1 h2 h3 h4 h5 h6 p li ul ol strong em a i br], attributes: %w[href]) }
  #         when 'if_xpath' # continue if xpath resolves
  #           html ||= safe_wringer_call { agent.get_file(use_wringer(url, render_js, scrape_options)) }
  #           page ||= Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
  #           page_data = page.xpath(algo)
  #           break if page_data.blank?
  #           page_data.each { |d| results_list << d.text }
  #         when 'unless_xpath' # continue unless xpath resolves
  #           html ||= safe_wringer_call { agent.get_file(use_wringer(url, render_js, scrape_options)) }
  #           page ||= Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
  #           page_data = page.xpath(algo)
  #           break if page_data.present?
  #         when 'xpath' # test
  #           html ||= safe_wringer_call { agent.get_file(use_wringer(url, render_js, scrape_options)) }
  #           # TODO: If response type is json then load json, otherwise load html in next line
  #           page ||= Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
  #           page_data = page.xpath(algo)
  #           page_data.each { |d| results_list << d.text }
  #         when 'css' # ok
  #           html ||= safe_wringer_call { agent.get_file(use_wringer(url, render_js, scrape_options)) }
  #           page ||= Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
  #           page_data = page.css(algo)
  #           page_data.each { |d| results_list << d.text }
  #         when 'time_zone' # test
  #           results_list << "time_zone: #{algo}"
  #           logger.info "*** Adding time_zone: #{algo}"
  #         when 'json' # ok
  #           ## use this pattern in source algorithm --> json=$json['name']
  #           html ||= safe_wringer_call { agent.get_file(use_wringer(url, render_js, scrape_options)) }
  #           page ||= Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
  #           json_scraped = JSON.parse(page.text)
  #           algo.gsub!('$json', 'json_scraped')
  #           results_list << eval(algo)
  #         else 
  #           results_list << ['abort_update',{error: "Missing valid prefix", algorithm: a}]
  #         end
  #       rescue SyntaxError => e
  #         #return ['abort_update', {error: e.message.squish, error_type: e.class, results_prior: results_list, algorithm_rescued: a}]
  #         core_message = e.message.lines.first.chomp # Only the first line!
  #         return ['abort_update', {error: core_message, error_type: e.class, results_prior: results_list, algorithm_rescued: a}]
  #       rescue  => e
  #         logger.error(" ****************** Error in scrape: #{e.inspect}")
  #         prior_preview = Array(results_list).flatten.map { |v| v.to_s[0,200] }.take(5)
  #         return ['abort_update', {
  #           error: core_message,
  #           error_type: e.class,
  #           results_prior_preview: prior_preview,
  #           algorithm_rescued: a.to_s[0, 500]
  #         }]
  #       end
  #     end
  #   end
  #   results_list 
  # end
  def process_algorithm(algorithm:, render_js: false, language: "en", url:, scrape_options: {})
    if legacy_sparql_algorithm?(algorithm)
      return process_algorithm_sparql_compat(
        algorithm: algorithm,
        render_js: render_js,
        url: url,
        scrape_options: scrape_options
      )
    end

    tracer = Dsl::Tracing::NullTracer.new 
    ctx = {
      url: url,
      render_js: render_js,
      scrape_options: process_algorithm_scrape_options(scrape_options),
      tracer: tracer
    }
    Dsl::Core::AlgorithmRunner.new(ctx).run(algorithm)
  end

  def process_algorithm_scrape_options(scrape_options)
    options = scrape_options.respond_to?(:deep_dup) ? scrape_options.deep_dup : {}
    options = options.with_indifferent_access if options.respond_to?(:with_indifferent_access)
    options = options.to_h if options.respond_to?(:to_h)

    return options unless options.is_a?(Hash)
    return options if process_algorithm_uses_cache_path?(options)

    options.merge(wringer_compatibility: true)
  end

  def process_algorithm_uses_cache_path?(scrape_options)
    options = scrape_options.respond_to?(:symbolize_keys) ? scrape_options.symbolize_keys : {}
    log_context = options[:log_context]
    log_context = log_context.to_h.symbolize_keys if log_context.respond_to?(:to_h)
    log_context ||= {}

    options[:website].present? ||
      options[:website_id].present? ||
      options[:force_scrape].present? ||
      options[:force_scrape_every_hrs].present? ||
      options[:mode].present? ||
      log_context[:website_id].present? ||
      log_context[:statement_id].present? ||
      log_context[:source_id].present? ||
      log_context[:webpage_id].present?
  end

  def legacy_sparql_algorithm?(algorithm)
    algorithm.to_s.strip.start_with?("sparql=")
  end

  def process_algorithm_sparql_compat(algorithm:, render_js:, url:, scrape_options:)
    sparql_clause = algorithm.to_s.strip.partition("=").last
    graph = safe_wringer_call do
      RDF::Graph.load(use_wringer(url, render_js, scrape_options))
    end
    return graph if abort_update_structure?(graph)

    sparql = "PREFIX schema: <http://schema.org/> select * where #{sparql_clause}"
    rows = SPARQL.execute(sparql, graph)
    [*(rows.count == 1 ? rows.first.answer.value : rows.map { |r| r.answer.value })]
  rescue StandardError => e
    ["abort_update", {
      error: e.message,
      error_type: e.class.to_s,
      source: "dsl_runner",
      step: "sparql"
    }]
  end


  def scrape(source, url, scrape_options = {})
    process_algorithm(algorithm: source.algorithm_value, render_js:source.render_js, language:source.language, url:url, scrape_options: scrape_options) #, cache_refreshed:, cache_changed:)
  end

  def is_condenser_formated_array(scraped_data)
    # check if scraped_data is already formated for condenser as an array in the case of hard coding (like event category).
    # example: scraped_data = ["[\"Manually added\",\"Category\",[\"Performance\" , \"http://ontology.artsdata.ca/Performance\"]]"]
    scraped_data[0][0] == '['
  rescue StandardError
    false
  end


  def convert_datetime(scraped_data)
    logger.info("Formatting dateTime with: #{scraped_data}")
    data = []
    scraped_data = Array(scraped_data)
    # check for time_zone
    time_zone = nil
    scraped_data.each do |t|
      next unless t.class == String
      if t.start_with?('time_zone:')
        time_zone = t.split(':')[1].strip
        scraped_data.delete(t)
      end
    end
    scraped_data.each do |t|
      data << if time_zone
                ISO_dateTime(t, time_zone)
              else
                ISO_dateTime(t)
              end
    end
    data.uniq!
    data
  end

  def convert_date(scraped_data)
    dates = convert_datetime(scraped_data)
    dates.map do |d|
      begin
        d.to_date 
      rescue => exception
        "input: #{scraped_data} error: #{exception}"
      end
    end
  end

  def format_datatype(scraped_data, property, webpage, statement_status: "initial")
    data = []
    if property.value_datatype == 'xsd:dateTime'
      data = convert_datetime(scraped_data)
    elsif property.value_datatype == 'xsd:date'
      data = convert_date(scraped_data)
    elsif property.value_datatype == 'xsd:anyURI'
      if scraped_data.present?
        if property.expected_class == 'EventStatusType'
          data << reconcile_event_status(scraped_data)
        elsif property.expected_class == 'EventTypeEnumeration'
          # Note: in properties UI switch Expected Class to EventType to use Artsdata
          data << reconcile_additional_type(scraped_data)
        elsif property.expected_class == 'EventAttendanceModeEnumeration'
          data << reconcile_attendance_mode(scraped_data)
        else
          if scraped_data.class == Array
            # Always reconcile when the state is "initial","missing","problem"
            # If the state is "ok", "update" then reconcile except performer and organizer.
            # Example: Performer that has been reviewed (ok) will not be reconciled.
           # if ["initial","missing","problem"].include?(statement_status) || !['http://schema.org/performer','http://schema.org/organizer'].include?(property.uri) 
              scraped_data.each do |uri_string|
                if uri_string.present? && !uri_string.include?("error:")# Do not try to link URIs with empty strings or errors
                  # TODO: Only reconcile location if original cache "based on:" text changed
                  linked_data = search_for_uri(uri_string, property, webpage)
                  return linked_data if abort_update_structure?(linked_data)

                  data << linked_data
                end
              end
            # end
          end
        end
      end
    elsif property.value_datatype == 'xsd:duration'
      scraped_data.each do |t|
        data << ISO_duration(t)
      end
    else
      data = scraped_data
    end
    if data.class == Array
      data = data.first if data.count == 1
    end
    data
  end

  def reconcile_event_status(scraped_data)
    str = ensure_array(scraped_data).join(' - ')
    result = [str, 'EventStatusType']
    if str.scan(/\b(Cancelled|Annulé|Annule)/i).present?
      result << ['EventCancelled', 'http://schema.org/EventCancelled']
    elsif str.scan(/\b(Postponed|Suspendu)/i).present?
      result << ['EventPostponed','http://schema.org/EventPostponed']
    elsif str.scan(/\b(Rescheduled|reporté|reporte)/i).present?
      result << ['EventRescheduled','http://schema.org/EventRescheduled']
    else
      result << ['EventScheduled','http://schema.org/EventScheduled']
    end
    result
  end

  def reconcile_additional_type(scraped_data)
    str = ensure_array(scraped_data).join(' - ')
    result =  [str, 'EventTypeEnumeration']
    if str.scan(/\b(Young public|Jeune public)/i).present?
      result << ['ChildrensEvent', 'http://schema.org/ChildrensEvent']
    end
    if str.scan(/\b(Comedy|Humour)/i).present?
      result << ['ComedyEvent', 'http://schema.org/ComedyEvent']
    end
    if str.scan(/\b(Dance|Danse)/i).present?
      result << ['DanceEvent', 'http://schema.org/DanceEvent']
    end
    if str.scan(/\b(Music|Musique|Chanson)/i).present?
      result <<  ['MusicEvent', 'http://schema.org/MusicEvent']
    end
    if str.scan(/\b(Theatre|Théâtre)/i).present?
      result << ['TheaterEvent', 'http://schema.org/TheaterEvent']
    end
    if str.scan(/\b(Screening|Movie|Cinéma)/i).present?
      result << ['TheaterEvent', 'http://schema.org/ScreeningEvent']
    end
    if str.scan(/\b(Performance)/i).present?
      result << ['Performance', 'http://ontology.artsdata.ca/Performance']
    end
    result
  end

  def reconcile_attendance_mode(scraped_data)
    str = ensure_array(scraped_data).join(' - ')
    result =  [str, 'EventAttendanceModeEnumeration']
    if str.scan(/\b(OfflineEventAttendanceMode)/i).present?
      result << ['In-person', 'http://schema.org/OfflineEventAttendanceMode']
    end
    if str.scan(/\b(OnlineEventAttendanceMode)/i).present?
      result << ['Online', 'http://schema.org/OnlineEventAttendanceMode']
    end
    if str.scan(/\b(MixedEventAttendanceMode)/i).present?
      result << ['Mixed', 'http://schema.org/MixedEventAttendanceMode']
    end
    result
  end



  def search_for_uri(uri_string, property_obj, current_webpage)
    # data structure of uri = ['name', 'rdfs_class', ['name', 'uri'], ['name','uri'],...]
    # use property object to determine class
    expected_classes = expected_classes_for(property_obj.expected_class)
    rdfs_class = expected_classes.first
    uris = [uri_string, rdfs_class]

    expected_classes.each do |expected_class|
      results = search_everywhere(uri_string, expected_class, current_webpage)
      if abort_update_structure?(results)
        return results if uris.length <= 2

        next
      end

      uris.concat(Array(results)[2..-1].to_a)
    end

    uris = deduplicate_uri_hits(uris, current_webpage)
    uris
  end

  def expected_classes_for(expected_class)
    classes = expected_class.to_s.split(",").map(&:strip).reject(&:blank?)
    classes = ["Organization", "Person"] if classes == ["Organization"]
    classes
  end

  # Used when refreshing and also when manually adding in Console
  def search_everywhere(uri_string, rdfs_class, current_webpage = nil)
    uri_string = uri_string.to_s.squish
    uris = [uri_string]
    uris << rdfs_class

    #############################
    # search Local Condenser DB
    #############################
    local_results = search_condenser(uri_string, rdfs_class)

    local_results[:data].each do |uri|
      if uri
        http_uri = uri[1].gsub('adr:', 'http://kg.artsdata.ca/resource/')
        uris << [uri[0], http_uri]
      end
    end

    # When nothing is found locally then search in artsdata.ca CC KG 
    if uris.count == 2  
      #############################
      # search KG
      #############################
      cckg_results = search_cckg(uri_string, rdfs_class, current_webpage)

      if cckg_results[:error]
        logger.error("*** search kg ERROR:  #{cckg_results}")
      else
        cckg_results[:data].each do |uri|
          uris << uri if uri
        end
      end

      if rdfs_class == 'Organization'
        cckg_results = search_cckg(uri_string, 'Person')
        if cckg_results[:error]
          logger.error("*** search kg ERROR:  #{cckg_results}")
        else
          cckg_results[:data].each do |uri|
            uris << uri if uri
          end
        end
      end
    end

    uris.uniq!
    uris
  end

  ####
  # hits = Statement.joins(source: :property)
  # .where(status: ['ok','updated'])
  # .where("lower(cache) LIKE ?", "%" + params[:query].downcase + "%")
  # .where({ sources: { selected: true, properties: { label: ['Name','alternateName'], rdfs_class: RdfsClass.where(name: params[:type]) } }  })
  # .distinct
  # .pluck(:cache, :webpage_id)

  def search_condenser(uri_string, expected_class) # returns a HASH
    # get names of all statements of expected_class

    expected_class = expected_classes_for(expected_class)

    hits = Statement.joins(source: :property)
                        .where(status: ['ok','updated'])
                        .where("lower(cache) LIKE ?", "#{uri_string.downcase}")
                        .where({ sources: { selected: true, properties: { label: ['Name','alternateName'], rdfs_class: RdfsClass.where(name: expected_class) } }  })
                        .pluck(:cache, :webpage_id)

    # get uris
    hits.each_with_index do |hit, index|
      webpage = Webpage.find(hit[1])
      hits[index][1] = webpage.rdf_uri if webpage
    end
    
    #################################################
    # REMOVE NAMES THAT CREATE MANY FALSE POSITIVES - until better analysis with NLP is available
    names_to_remove = SearchException.where(rdfs_class: RdfsClass.where(name: expected_class)).pluck(:name)
    hits.reject! { |hit| names_to_remove.include? hit[0] }
    #################################################
    
    { data: hits.uniq }
    # #TODO: ????also check (s.webpage.website == webpage.website)
  end

  def deduplicate_uri_hits(uris, current_webpage)
    base = uris.first(2)
    hits = Array(uris[2..-1]).compact
    hits = hits.reject do |uri|
      uri.is_a?(Array) && current_webpage.present? && uri[1] == current_webpage.rdf_uri
    end
    hits = hits.uniq { |uri| uri.is_a?(Array) ? uri[1] : uri }
    base + hits
  end

  def abort_update_structure?(value)
    value.is_a?(Array) && value.first == "abort_update" && value.second.is_a?(Hash)
  end

  def linked_data_abort(error:, query:, expected_class:, source: "search_cckg")
    ["abort_update", {
      error: error.to_s,
      error_type: "LinkedDataLookupError",
      source: source,
      query: query,
      expected_class: expected_class
    }]
  end

  def clean_query?(str)
    return false if str.blank?

    str.length < 60 &&
      str !~ /\b(and|et)\b/i &&
      str !~ /,|&/
  end

  def normalize_string(s)
    s.to_s
    .downcase
    .gsub('&', ' and ')
    .gsub(/[^a-z0-9\s]/, ' ')
    .squeeze(' ')
    .strip
  end

  def extract_province(webpage)
    return nil unless webpage&.website&.respond_to?(:province)

    webpage.website.province
  end

  def search_cckg(str, rdfs_class, webpage = nil) # returns a HASH
    return { data: [] } if str.length <= 3

    clean = clean_query?(str)
    province = extract_province(webpage)

    use_structured_query = rdfs_class == "Place" && clean && province.present?

    begin
      hits = fetch_cckg_hits(str, rdfs_class, webpage, use_structured_query)
    rescue StandardError => e
      return {
        error: "No server running at #{artsdata_recon_url}",
        method: 'search_cckg',
        message: "#{e.inspect}"
      }
    end

    Rails.logger.debug { "[CCKG] hits=#{hits.size}" }
    best_hits = select_cckg_hits(hits, str, rdfs_class, webpage, clean)
    Rails.logger.debug { "[CCKG] best_hits=#{best_hits.size}" }
    filtered_hits = filter_cckg_hits(best_hits, str, clean)
    Rails.logger.debug { "[CCKG] filtered_hits=#{filtered_hits.size}" }
    result = map_cckg_results(filtered_hits)

    { data: result }
  end

  def fetch_cckg_hits(str, rdfs_class, webpage, use_structured_query)
    recon_type = if rdfs_class == "EventType"
                  "ado:EventType"
                else
                  rdfs_class
                end

    province = extract_province(webpage)

    if use_structured_query
      payload = {
        q0: {
          query: str,
          type: "schema:Place",
          properties: [
            {
              pid: "schema:address/schema:addressRegion",
              v: province
            }
          ]
        }
      }

      response = HTTParty.get(
        "#{artsdata_recon_url}?queries=#{CGI.escape(payload.to_json)}"
      )

      response.dig("q0", "result") || []
    else
      escaped_query = CGI.escape(CGI.unescapeHTML(str))
                         .gsub('+', '%20')
                         .gsub('%3A', ':')
      response = HTTParty.get(
        "#{artsdata_recon_url}?query=#{escaped_query}&type=#{recon_type}"
      )

      response["result"] || []
    end
  end

  def select_cckg_hits(hits, str, rdfs_class, webpage, clean)
    province = extract_province(webpage)
    has_webpage_province_context = province.present?
    missing_province_context = !has_webpage_province_context && webpage&.website&.respond_to?(:province)

    if hits.size <= 1
      hits
    elsif clean && !(rdfs_class == "Place" && missing_province_context)
      best = select_best_hit(hits)
      best ? [best] : []
    else
      hits
    end
  end

  def filter_cckg_hits(hits, str, clean)
    if clean
      normalized_query = normalize_string(CGI.unescapeHTML(str))
      hits.select do |h|
        next true if h["match"] == true

        hit_name = normalize_string(h["name"])
        normalized_query.include?(hit_name) || hit_name.include?(normalized_query)
      end
    else
      normalized_query = normalize_string(CGI.unescapeHTML(str))
      filter_noisy_hits(hits, normalized_query)
    end
  end

  def filter_noisy_hits(hits, normalized_query)
    noisy_hits = hits.select do |h|
      raw_name = h["name"].to_s
      name = normalize_string(raw_name)
      trailing_segment = normalize_string(raw_name.split('-').last.to_s)

      (name.length >= 8 && normalized_query.include?(name)) ||
        (trailing_segment.length >= 8 && normalized_query.include?(trailing_segment))
    end

    noisy_hits.reject do |candidate|
      candidate_name = normalize_string(candidate["name"])
      noisy_hits.any? do |other|
        other != candidate &&
          normalize_string(other["name"]).include?(candidate_name) &&
          normalize_string(other["name"]).length > candidate_name.length
      end
    end
  end

  def map_cckg_results(hits)
    result = Array(hits).map do |h|
      [h["name"], "http://kg.artsdata.ca/resource/#{h["id"]}"]
    end

    result.uniq! { |r| r[1] }
    result
  end

  def select_best_hit(hits)
    return nil if hits.blank?

    auto = hits.select { |h| h["match"] == true }
    return auto.first if auto.size == 1

    hits.max_by { |h| h["score"].to_f }
  end

  def ISO_duration(duration_str)
    begin
      duration_in_seconds = ChronicDuration.parse(duration_str)
      duration_iso8601 = if duration_in_seconds.blank?
                           '' # Leave statement empty so it gets ignored in the triple store.
                         else
                           "PT#{duration_in_seconds}S"
                         end
    rescue StandardError
      duration_iso8601 = "Error in duration: #{duration_str}"
    end
    duration_iso8601
  end

  def french_to_english_month(date_time)
    date_time.downcase
             .gsub(/janvier|février|fév|mars|avr|mai|juin|juillet|juil|août|aou|aoû|septembre|octobre|novembre|décembre|déc/, 'janvier' => 'JAN', 'février' => 'FEB', 'fév' => 'FEB', 'mars' => 'MAR', 'avril' => 'APR', 'avr' => 'APR', 'mai' => 'MAY', 'juin' => 'JUN', 'juillet' => 'JUL', 'juil' => 'JUL', 'aou' => 'AUG', 'août' => 'AUG', 'aoû' => 'AUG', 'septembre' => 'SEP', 'octobre' => 'OCT', 'novembre' => 'NOV', 'décembre' => 'DEC', 'déc' => 'DEC')
  end

  def ISO_dateTime(date_time, time_zone = 'Eastern Time (US & Canada)')
    begin
      current_timezone = Time.zone
      Time.zone = time_zone
      d = Time.zone.parse(french_to_english_month(date_time)
                               .gsub(/ h /, 'h') # French times usually have spaces around the 'H'
                               .gsub(/halifax/i, '')) # Halifax is used in timezone names. Remove it to avoid confusion.

      # if the dateTime is midnight then assume that there is no known time and convert to a Date Object instead of Time object.
      d = d.to_date if d == d.midnight

      Time.zone = current_timezone

      iso_date_time = d.iso8601
    rescue NoMethodError => e
      iso_date_time = ""
    rescue StandardError => e
      iso_date_time = "Bad input for date/time: #{date_time}.  (#{e.inspect})"
    end
    iso_date_time
  end

  def format_language(language)
    '@' + language if language.present?
  end

  def build_key(statement) # for JSON output
    new_key = statement.source.property.label.downcase.sub(' ', '_')
    if statement.source.language.present?
      new_key = "#{new_key}_#{statement.source.language}"
    end
    new_key
  end

  def process_linked_data_removal(statement_cache, uri_to_delete, class_to_delete, label_to_delete)
    statement_cache = [statement_cache] if statement_cache[0].class != Array

    updated_cache = false
    statement_cache.each_with_index do |c, i|
      next unless c[0] == 'Manually deleted' || c[0] == 'Manually added'

      c.each_with_index do |uri_pair, x|
        if uri_pair[1] == uri_to_delete
          statement_cache[i].delete_at(x)
          updated_cache = true
        end
      end
      statement_cache.delete_at(i) if c.length < 3
    end

    # if no change then store the link to delete
    unless updated_cache

      link_added = false
      statement_cache.each_with_index do |c, i|
        if c[0] == 'Manually deleted'
          statement_cache[i] << [label_to_delete, uri_to_delete]
          link_added = true
        end
      end
      unless link_added
        statement_cache << ['Manually deleted', class_to_delete, [label_to_delete, uri_to_delete]]
      end

    end

    statement_cache
  end

  def preserve_manual_links _data, old_data
    return _data if old_data.blank?

    _data = [_data] if _data[0].class != Array
    begin
      _old_cache = JSON.parse(old_data)
    rescue StandardError
      _old_cache = old_data
    end
    _old_cache = [_old_cache] if _old_cache[0].class != Array
    _old_cache.each do |c|
      _data << c if c[0] == 'Manually added' || c[0] == 'Manually deleted'
    end
    _data
  end

  def artsdata_recon_url
    if Rails.env.development?  || Rails.env.test?
      "http://localhost:#{ARTSDATA_API_PORT}/recon"
    else
      'http://api.artsdata.ca/recon'
    end
  end



  # Activate statement's source and selected_indvidual across all events
  # INPUT: statement ActiveRecord
  # OUPUT: sources ActiveRecord::Relation
  def activate_source(statement)
    #get all statements about this property/language for the resource(individual)
    
    sources = Source.where(website_id: statement.webpage.website.id, property_id: statement.source.property.id, language: statement.source.language )

    sources.each do |source|
      if source.id != statement.source.id
        if source.selected 
          source.update(selected: false)
          Statement.where(source: source, selected_individual: true)  
                   .update_all(selected_individual: false) # turn off all statements that were on by template
        end
      else # the one to activate
        source.update(selected: true)
        Statement.includes(:source)
                  .where(source: source, selected_individual: false)  # get all statements where currently 
                  .update_all(selected_individual: true)
      end
    end
    # Fix manual overrides
    override_statements = Statement.includes(:source).where(source: sources, sources: {selected: false}, selected_individual: true )
    
    override_statements.each do |s|
      # get other statements for same property/language/webpage
      related_statements = Statement.includes(:source).where(webpage_id: s.webpage_id, sources: { property_id: s.source.property.id, language: s.source.language})
      related_statements.each do  |related_stat|
        if related_stat.id != s.id
          related_stat.update(selected_individual: false)
        end
      end
    end

    sources
  end

  # Ensure an unknown parameter is an Array
  # "one" => ["one"]
  # "[\"one\"],[\"two\"]" => ["one","two"]
  # ["one","two"] => ["one","two"]
  def ensure_array(unknown)
    return unknown if unknown.class == Array
    begin
      # try to convert unknown string to array
      JSON.parse(unknown.to_s)
    rescue JSON::ParserError
      # make string or existing array to array
      Array(unknown)
    end
  end

  # def logger
  #  @logger ||= Logger.new(STDOUT)
  # end
end

# app/helpers/statements_helper.rb (minimal example)
