require "test_helper"

class DslContractTest < ActiveSupport::TestCase
  def build_runner(html: "<html></html>")
    stub_request(:get, /wring/).to_return(status: 200, body: html)

    Dsl::DslAlgorithmRunner.new(
      url: "http://example.com",
      render_js: false,
      scrape_options: {},
      tracer: Dsl::DslNullTracer.new
    )
  end

  # -------------------------
  # CONTROL FLOW
  # -------------------------

  test "if_xpath halts when no match" do
    runner = build_runner(html: "<html></html>")
    result = runner.run("if_xpath=//title; xpath=//h1")
    assert_empty result
  end

  test "if_xpath continues when match exists" do
    html = "<html><title>T</title><h1>H</h1></html>"
    runner = build_runner(html: html)

    result = runner.run("if_xpath=//title; xpath=//h1")
    assert_equal ["H"], result
  end

  test "unless_xpath halts when match exists" do
    html = "<html><title>T</title><h1>H</h1></html>"
    runner = build_runner(html: html)

    result = runner.run("unless_xpath=//title; xpath=//h1")
    assert_empty result
  end

  test "unless_xpath continues when no match" do
    html = "<html><h1>H</h1></html>"
    runner = build_runner(html: html)

    result = runner.run("unless_xpath=//title; xpath=//h1")
    assert_equal ["H"], result
  end

  # -------------------------
  # REPLACEMENT (NO ACCUMULATION)
  # -------------------------

  test "xpath replaces previous results" do
    html = "<html><p>A</p><h1>H</h1></html>"
    runner = build_runner(html: html)

    result = runner.run("xpath=//p/text(); xpath=//h1/text()")
    assert_equal ["H"], result
  end

  test "ruby replaces previous results" do
    html = "<html><p>a</p><p>b</p></html>"
    runner = build_runner(html: html)

    result = runner.run("xpath=//p/text(); ruby=$array.map(&:upcase)")
    assert_equal %w[A B], result
  end

  test "json replaces previous results" do
    html = '{"name":"test"}'
    runner = build_runner(html: html)

    result = runner.run("json=$json['name']")
    assert_equal "test", result
  end

  # -------------------------
  # CONTEXT MUTATION
  # -------------------------

  test "url step does not change results" do
    stub_request(:get, /example.com/).to_return(status: 200, body: "<html></html>")

    runner = Dsl::DslAlgorithmRunner.new(
      url: "http://example.com",
      render_js: false,
      scrape_options: {},
      tracer: Dsl::DslNullTracer.new
    )

    result = runner.run("url='http://example.com'; xpath=//h1")
    assert_empty result
  end

  # -------------------------
  # MANUAL
  # -------------------------

  test "manual returns constant value" do
    runner = build_runner

    result = runner.run("manual=Hello")
    assert_equal ["Hello"], result
  end

  # -------------------------
  # ABORT HANDLING
  # -------------------------

  test "invalid ruby returns abort_update" do
    runner = build_runner

    result = runner.run("ruby=invalid ruby(")
    assert_equal "abort_update", result.first
    assert result.last[:error]
  end

  # -------------------------
  # NO ACCUMULATION GUARANTEE
  # -------------------------

  test "no step accumulates results implicitly" do
    html = "<html><p>a</p><h1>b</h1></html>"
    runner = build_runner(html: html)

    result = runner.run("xpath=//p/text(); xpath=//h1/text()")
    assert_not_includes result, "a"
    assert_equal ["b"], result
  end

  # ⚠️ CONTRACT TEST — DO NOT SIMPLIFY
  # This test reflects real-world DSL behavior used in production.
  # If this breaks, the DSL runner contract has been violated.
  # SENTINEL TEST
  # Purpose:
  # Ensures real-world extraction semantics are preserved across:
  # Wringer → Condenser → DSL
  #
  # Known issue:
  # Currently failing due to extraction drift.
  # DO NOT REMOVE — used as regression indicator.
  test "real world ticket extraction pipeline preserves semantics" do
    html = <<~HTML
      <html>
        <body data-reference="123">
          <a rel="noopener" href="https://example.com/page"></a>
          <script type="application/json">
            {"event_buy_ticket_url":"https://lepointdevente.com/event/123"}
          </script>
          <p id="ctl00_ContentPlaceHolder_EventDetails">
            <span class="DateAndTime">Jan 1, 2026 8:00 PM</span>
          </p>
        </body>
      </html>
    HTML

    stub_request(:get, /example.com/).to_return(status: 200, body: html)

    # Mock LPDV JSON response
    stub_request(:get, %r{lepointdevente.com/plugins/rates}).to_return(
      status: 200,
      body: {
        rates: [
          { "price" => 25.0 },
          { "price" => 30.5 },
          { "price" => nil } # ignored
        ]
      }.to_json
    )

    runner = Dsl::DslAlgorithmRunner.new(
      url: "http://example.com",
      render_js: false,
      scrape_options: {},
      tracer: Dsl::DslNullTracer.new
    )

    dsl = <<~DSL
      xpath=//a[@rel='noopener']/@href
      ;ruby=$array.reject{|e| e =~ /madisonweb/}
      ;ruby=[begin
        cands = $array
        lpdv = cands.find{|u| u =~ /lepointdevente\\.com/i}
        other = cands.find{|u| u !~ /facebook\\.com/i}
        fb = cands.find{|u| u =~ /facebook\\.com/i}
        [lpdv || other || fb].compact
      end]
      ;renderjs_url=$array.first
      ;xpath=//script[@type='application/json']/text()
      ;ruby=[$array.first, $array.select{|s| s.include?('event_buy_ticket_url')}]
      ;ruby=$array = [
        $array.first,
        Array($array[1..-1]).flatten.grep(String)
          .map { |s| s[/event_buy_ticket_url":"([^"]*)"/, 1] }
          .compact.uniq
      ].flatten
      ;ruby=begin
        cands = $array
        lpdv = cands.find{|u| u =~ /lepointdevente\\.com/i}
        other = cands.find{|u| u !~ /facebook\\.com/i}
        fb = cands.find{|u| u =~ /facebook\\.com/i}
        [lpdv || other || fb].compact
      end
      ;url=$array.first
      ;ruby=$array = []
      ;if_xpath=//body/@data-reference
      ;url='https://lepointdevente.com/plugins/rates/' + '123'
      ;json=$json.dig('rates')
      ;ruby=
        tickets = nil
        $array.reverse.each do |el|
          if el.is_a?(Array) && el.any? { |x| x.is_a?(Hash) && x.key?('price') }
            tickets = el
            break
          end
        end

        if tickets
          tickets
            .select { |x| x.is_a?(Hash) && x.key?('price') && !x['price'].nil? }
            .map { |x| x['price'].to_f.round(2) }
        else
          []
        end
    DSL

    result = runner.run(dsl)

    assert_equal [25.0, 30.5], result
  end
end