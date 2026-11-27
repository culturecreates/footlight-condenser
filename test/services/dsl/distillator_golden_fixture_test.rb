require "test_helper"

class DistillatorGoldenFixtureTest < ActiveSupport::TestCase
  include StatementsHelper

  FetchResult = Struct.new(
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

  FIXTURE_ROOT = Rails.root.join("test/fixtures/files/distillator_dsl")

  test "golden fixtures cover real DSL patterns through the Distillator runner path" do
    cases.each do |fixture_case|
      body = File.read(FIXTURE_ROOT.join(fixture_case.fetch(:fixture_file)))
      url = fixture_case.fetch(:url)

      fetch_stub = lambda do |**kwargs|
        assert_equal url, kwargs[:uri], failure_prefix(fixture_case, "unexpected fetch uri #{kwargs[:uri].inspect}")
        assert_equal false, kwargs[:render_js], failure_prefix(fixture_case, "expected render_js=false")
        assert_equal true, kwargs[:include_fragment], failure_prefix(fixture_case, "expected include_fragment=true")
        build_fetch_result(url: url, body: body)
      end

      singleton = class << Distillator::FetchCacheStore
        self
      end
      original_fetch = Distillator::FetchCacheStore.method(:fetch)
      singleton.send(:define_method, :fetch) do |**kwargs|
        fetch_stub.call(**kwargs.symbolize_keys)
      end

      result, trace = begin
        run_dsl(
          algorithm: fixture_case.fetch(:algorithm_value),
          url: url,
          trace: true
        )
      ensure
        singleton.send(:define_method, :fetch, original_fetch)
      end

      actual = Array(result)
      expected = fixture_case.fetch(:expected_array)

      assert_equal expected, actual, failure_prefix(fixture_case, "expected #{expected.inspect}, got #{actual.inspect}")

      trace_types = Array(trace).map { |event| event[:type] || event["type"] }
      fixture_case.fetch(:expected_trace_presence).each do |trace_type|
        assert_includes trace_types, trace_type, failure_prefix(fixture_case, "missing trace step #{trace_type.inspect} in #{trace_types.inspect}")
      end
    end
  end

  private

  def cases
    [
      {
        algorithm_value: "xpath=//title",
        fixture_file: "simple_title.html",
        url: "https://fixtures.example/distillator-dsl/simple-title",
        expected_array: ["Simple Fixture Title"],
        expected_trace_presence: ["xpath"]
      },
      {
        algorithm_value: "xpath=//meta[@property='og:title']/@content",
        fixture_file: "simple_title.html",
        url: "https://fixtures.example/distillator-dsl/og-title",
        expected_array: ["OG Fixture Title"],
        expected_trace_presence: ["xpath"]
      },
      {
        algorithm_value: "xpath_sanitize=//div[@class='description'];ruby=$array.map { |str| str.squish }",
        fixture_file: "price_block.html",
        url: "https://fixtures.example/distillator-dsl/price-block",
        expected_array: ["Opening night gala"],
        expected_trace_presence: ["xpath_sanitize", "ruby"]
      },
      {
        algorithm_value: "xpath=//script[@type='application/ld+json'];ruby=JSON.parse($array[0]).dig('name')",
        fixture_file: "json_ld_event.html",
        url: "https://fixtures.example/distillator-dsl/json-ld",
        expected_array: ["JSON-LD Fixture Event"],
        expected_trace_presence: ["xpath", "ruby"]
      },
      {
        algorithm_value: "xpath=//a/@href;ruby=$array.map { |url| \"footlight:test_\#{url.split('/').last}\" }",
        fixture_file: "resource_list.html",
        url: "https://fixtures.example/distillator-dsl/resource-list",
        expected_array: ["footlight:test_opening-night", "footlight:test_main-hall"],
        expected_trace_presence: ["xpath", "ruby"]
      }
    ]
  end

  def build_fetch_result(url:, body:)
    FetchResult.new(
      status: :ok,
      body: body,
      html: body,
      headers: { content_type: "text/html" },
      final_url: url,
      redirect_chain: [url],
      http_response_code: 200,
      signals: { "network_status" => "ok", "content_type" => "html" },
      hints: [],
      duration_ms: 1.0,
      cache_hit: false,
      cache_write: true,
      cache_reason: "missing_cache",
      uri_key: CGI.escape(url),
      normalized_url: url,
      fetch_path: "native"
    )
  end

  def failure_prefix(fixture_case, detail)
    "fixture=#{fixture_case[:fixture_file]} algorithm=#{fixture_case[:algorithm_value]} #{detail}"
  end
end
