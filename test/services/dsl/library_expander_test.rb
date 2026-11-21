require "test_helper"

class Dsl::LibraryExpanderTest < ActiveSupport::TestCase
  include DslRunnerTestHelper

  test "seeded meta title and generic filters equal explicit instructions on identical input" do
    html = '<html><meta property="og:title" content=" My Title "><p> A </p><p> B </p></html>'
    runner, trace = build_runner_with_html(html: html)
    result = runner.run('$$META_TITLE$$;$$ARRAY_SQUISH$$;$$ARRAY_UNIQ$$')
    explicit, = build_runner_with_html(html: html)
    assert_equal explicit.run("xpath=//meta[@property='og:title']/@content;ruby=$array.map{|e| e.squish};ruby=$array.uniq"), result
    assert_equal ["My Title"], result
    assert_equal "META_TITLE", trace.to_h.first[:library].first[:name]
    assert_equal 1, runner.library_evidence.first[:revision]
    assert_includes runner.library_evidence.first[:body], "og:title"
  end

  test "preserves nested array accumulation and the requested ARRAY_FIRST contract" do
    runner, = build_runner_with_html(html: '<p> A </p><p> B </p>')
    assert_equal ["A", "B"], runner.run('ruby=["saved"];$$ARRAY_SAVE$$;xpath=//p;$$ARRAY_FIRST$$')
    [[], [" A "]].each do |state|
      runner, = build_runner
      assert_equal state, runner.run("ruby=#{state.inspect};$$ARRAY_FIRST$$")
    end
  end

  test "nested blocks are snapshotted with body revision and preserve caller locals" do
    entry = DslLibraryEntry.create!(name: "TEST_BLOCK", body: '$$CURRENT_URL$$;ruby=[$array]')
    runner, = build_runner(url: "https://example.org/event")
    assert_equal ["https://example.org/event"], runner.run('$$TEST_BLOCK$$')
    evidence = runner.library_evidence.find { |item| item[:name] == entry.name }
    assert_equal entry.body, evidence[:body]
    assert_equal Digest::SHA256.hexdigest(entry.body), evidence[:sha256]
  end

  test "plain DSL and URL placeholders do not cause a library query or substitution inside strings" do
    DslLibraryEntry.expects(:pluck).never
    runner, = build_runner
    assert_equal ["$$META_TITLE$$"], runner.run('ruby=["$$META_TITLE$$"]')
    assert_equal "https://explicit.example", runner.run('ruby="https://explicit.example"')
  end

  test "unknown names and cycles abort before any extraction and restore thread state" do
    Thread.current[:dsl_array] = ["caller"]
    runner, trace = build_runner
    result = runner.run('ruby=raise "must not execute";$$MISSING_LIBRARY_NAME$$')
    assert_equal "LibraryExpansionError", result.last[:error_type]
    assert_includes result.last[:error], "MISSING_LIBRARY_NAME"
    assert_equal ["caller"], Thread.current[:dsl_array]
    assert_equal "library", trace.to_h.first[:type]
    overrides = {"A" => {name: "A", body: '$$B$$', revision: 1}, "B" => {name: "B", body: '$$A$$', revision: 1}}
    error = assert_raises(Dsl::LibraryExpander::Error) { Dsl::LibraryExpander.call('$$A$$', overrides: overrides) }
    assert_includes error.message, "Circular"
  ensure
    Thread.current[:dsl_array] = nil
  end

  test "expansion depth and size are bounded" do
    body = Array.new(1001, 'ruby=[]').join(';')
    assert_raises(Dsl::LibraryExpander::Error) do
      Dsl::LibraryExpander.call('$$HUGE$$', overrides: {"HUGE" => {name: "HUGE", body: body, revision: 1}})
    end
  end
  test "every starter entry preserves the exact explicit DSL result" do
    html = '<html><title>Document</title><meta property="og:title" content="OG"><meta property="og:image" content="image.jpg"><meta property="og:description" content="Description"><script type="application/ld+json">{"name":"Event"}</script></html>'
    DslLibraryEntry.order(:name).each do |entry|
      macro, = build_runner_with_html(html: html)
      explicit, = build_runner_with_html(html: html)
      prefix = 'ruby=[" A "," A "," B "];'
      assert_equal explicit.run(prefix + entry.body), macro.run(prefix + "$$#{entry.name}$$"), entry.name
    end
  end

  test "one execution uses one library snapshot even if a body changes during that execution" do
    entry = DslLibraryEntry.create!(name: "SNAPSHOT_CASE", body: 'ruby=["before"]')
    runner, = build_runner
    algorithm = "$$SNAPSHOT_CASE$$;ruby=DslLibraryEntry.find(#{entry.id}).update!(body: 'ruby=[\"after\"]');$$SNAPSHOT_CASE$$"
    assert_equal ["before"], runner.run(algorithm)
    assert_equal 1, runner.library_evidence.find { |item| item[:name] == entry.name }[:revision]
    next_run, = build_runner
    assert_equal ["after"], next_run.run('$$SNAPSHOT_CASE$$')
  end

end
