module DslRunnerTestHelper
  FETCH_RESPONSE_CLASS = Struct.new(
    :status,
    :body,
    :html,
    :headers,
    :final_url,
    :redirect_chain,
    :http_response_code,
    :signals,
    :hints,
    :duration_ms,
    :cache_hit,
    :cache_write,
    :cache_reason,
    :uri_key,
    :normalized_url,
    :fetch_path,
    keyword_init: true
  )

  def build_runner(url: "http://example.local", tracer: Dsl::Tracing::TraceCollector.new, scrape_options: {}, render_js: false)
    runner = Dsl::Core::AlgorithmRunner.new(
      url: url,
      render_js: render_js,
      scrape_options: scrape_options,
      tracer: tracer
    )

    [runner, tracer]
  end

  def build_runner_with_html(html: "<html></html>", url: "http://example.local", tracer: Dsl::Tracing::TraceCollector.new, scrape_options: {}, render_js: false)
    runner, tracer = build_runner(
      url: url,
      tracer: tracer,
      scrape_options: scrape_options,
      render_js: render_js
    )

    runner.instance_variable_set(:@html, html)
    runner.instance_variable_set(:@page, Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s))

    [runner, tracer]
  end

  def build_runner_with_text(text:, url: "http://example.local", tracer: Dsl::Tracing::TraceCollector.new, scrape_options: {}, render_js: false)
    runner, tracer = build_runner(
      url: url,
      tracer: tracer,
      scrape_options: scrape_options,
      render_js: render_js
    )

    runner.instance_variable_set(:@html, text)
    runner.instance_variable_set(:@page, Struct.new(:text).new(text))

    [runner, tracer]
  end

  def build_compat_runner(url: "http://example.local", tracer: Dsl::Tracing::TraceCollector.new, scrape_options: {}, render_js: false)
    build_runner(
      url: url,
      tracer: tracer,
      scrape_options: scrape_options.merge(wringer_compatibility: true),
      render_js: render_js
    )
  end

  def expect_no_fetch_seams
    Distillator::FetchCacheStore.expects(:fetch).never
    Dsl::Support::WringerClient.any_instance.expects(:fetch).never
  end

  def assert_no_wringer_requests
    wring_path = %r{https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0):(3000|3009)/websites/wring}
    assert_not_requested :any, wring_path
  end

  def distillator_fetch_response(
    status: :ok,
    body: "<html><body><h1>Title</h1></body></html>",
    html: nil,
    headers: { content_type: "text/html" },
    final_url: "http://example.local/start",
    redirect_chain: nil,
    http_response_code: 200,
    signals: {},
    hints: [],
    duration_ms: 0,
    cache_hit: false,
    cache_write: true,
    cache_reason: "missing_cache",
    uri_key: nil,
    normalized_url: nil,
    fetch_path: "native"
  )
    url = final_url

    FETCH_RESPONSE_CLASS.new(
      status: status,
      body: body,
      html: html || body,
      headers: headers,
      final_url: final_url,
      redirect_chain: redirect_chain || [final_url],
      http_response_code: http_response_code,
      signals: signals,
      hints: hints,
      duration_ms: duration_ms,
      cache_hit: cache_hit,
      cache_write: cache_write,
      cache_reason: cache_reason,
      uri_key: uri_key || CGI.escape(url),
      normalized_url: normalized_url || url,
      fetch_path: fetch_path
    )
  end
end
