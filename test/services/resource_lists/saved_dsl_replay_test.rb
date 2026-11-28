# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "json"
require "digest"
require "fileutils"
require_relative "../../../app/services/resource_lists/saved_dsl_replay"

class SavedDslReplayTest < Minitest::Test
  URL = "https://www.tourismeshawinigan.com/evenements/?search_query&categories%5B0%5D=culture&page=1"

  def setup
    @dir = Dir.mktmpdir
    @query = ResourceLists::NumberedPageQuery.new(start_url: URL)
    @captures = []
    @audit = []
    (1..4).each do |page|
      html = "<html>page #{page}</html>"
      File.binwrite(File.join(@dir, "page#{page}.html"), html)
      @captures << { "page" => page, "url" => @query.url_for(page),
        "final_url" => @query.url_for(page), "status" => 200,
        "sha256" => Digest::SHA256.hexdigest(html) }
      @audit << { "page" => page, "url" => @query.url_for(page),
        "status" => page < 3 ? "labeled_forward_observed" : "no_forward_observed",
        "labeled_next_url" => page < 3 ? @query.url_for(page + 1) : nil }
    end
    save
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def save
    File.binwrite(File.join(@dir, "probe.json"),
      JSON.generate("page_parameter" => "page", "captures" => @captures))
    File.binwrite(File.join(@dir, "semantic-next-audit.json"),
      JSON.generate("captures" => @audit))
  end

  def replay(&block)
    ResourceLists::SavedDslReplay.call(directory: @dir, algorithm: "xpath=//a",
      run_dsl: block || ->(algorithm:, url:, html:) { [html] })
  end

  def test_replay_stops_at_first_terminal_not_out_of_range
    result = replay
    assert_equal "dsl_replayed_parity_unverified", result.status
    assert_equal 3, result.terminal_page
    assert_equal [1, 2, 3], result.pages.map { |row| row[:page] }
    assert_equal 3, result.total_values
  end

  def test_missing_terminal
    @audit[2]["status"] = "labeled_forward_observed"
    @audit[2]["labeled_next_url"] = @query.url_for(4)
    @audit[3]["status"] = "labeled_forward_observed"
    @audit[3]["labeled_next_url"] = @query.url_for(5)
    save
    assert_includes replay.errors.first, "broken_semantic_next_chain"
  end

  def test_tampered_html_fails_closed
    File.binwrite(File.join(@dir, "page2.html"), "other")
    assert_includes replay.errors, "snapshot_sha_mismatch:2"
  end

  def test_changed_filter_page_fails_closed
    @captures[1]["url"] = @captures[1]["url"].sub("culture", "theatre")
    save
    assert_includes replay.errors, "broken_semantic_next_chain:1"
  end

  def test_semantic_audit_disagreement
    @audit[1]["url"] = @audit[1]["url"].sub("culture", "theatre")
    save
    assert_includes replay.errors, "mismatched_semantic_audit:2"
  end

  def test_dsl_abort_is_inconclusive
    result = replay { |algorithm:, url:, html:| ["abort_update", { "error_type" => "FetchUnsupported" }] }
    assert_includes result.errors, "dsl_abort:1:FetchUnsupported"
  end

  def test_empty_dsl_is_inconclusive
    assert_includes replay { |algorithm:, url:, html:| [] }.errors, "empty_dsl_page:1"
  end

  def test_unexpected_output_shape
    assert_includes replay { |algorithm:, url:, html:| "string" }.errors, "unexpected_dsl_output_shape:1"
  end

  def test_duplicate_values_are_reported_not_silently_removed
    result = replay { |algorithm:, url:, html:| ["x"] }
    assert_equal 2, result.duplicate_values
    assert_equal ["x"], result.pages.first[:values]
  end

  def test_passes_original_algorithm_url_and_saved_html_to_existing_runner
    called = []
    replay { |algorithm:, url:, html:| called << [algorithm, url, html]; ["one"] }
    assert_equal 3, called.size
    assert_equal "xpath=//a", called.first[0]
    assert_equal @query.url_for(1), called.first[1]
  end

  def test_inconclusive_semantic_next
    @audit[1]["status"] = "numbered_forward_only"
    save
    assert_includes replay.errors.first, "inconclusive_semantic_next:2"
  end
end
