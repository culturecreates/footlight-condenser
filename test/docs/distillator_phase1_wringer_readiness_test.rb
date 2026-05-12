require "test_helper"

class DistillatorPhase1WringerReadinessTest < ActiveSupport::TestCase
  DOC_PATH = Rails.root.join("docs", "distillator_phase1_wringer_readiness.md")
  ALLOWED_STATUSES = %w[legacy-only native shadow-only tested open].freeze

  REQUIRED_BEHAVIORS = [
    "GET /websites/wring route",
    "raw response format",
    "json response format",
    "html redirect/default response",
    "invalid params no_content behavior",
    "/websites.json?term lookup",
    "URI key generation",
    "no-scheme URL handling",
    "query preservation",
    "fragment exclusion by default",
    "fragment inclusion with include_fragment",
    "CGI.escape uri_key storage",
    "cache hit",
    "force_scrape",
    "force_scrape_every_hrs",
    "successful 2xx cache update",
    "failed 404 metadata update without overwriting last successful HTML",
    "scrape_date",
    "successful_refresh",
    "http_response_code",
    "headers",
    "signals",
    "hints",
    "final_url",
    "redirect_chain",
    "absolute_src rewriting for src and href",
    "json_post behavior",
    "use_phantomjs behavior",
    "PhantomJS missing-key fallback",
    "iframe special case",
    "ERB delimiter escaping",
    "initial URL guard",
    "redirect URL guard",
    "SSL/Mechanize/Socket error metadata",
    "materialized cache health summary",
    "export invariance",
    "legacy/internal fetch parity",
    "default legacy mode",
    "replay fixture compatibility"
  ].freeze

  test "readiness document exists" do
    assert File.exist?(DOC_PATH), "Expected #{DOC_PATH} to exist"
  end

  test "all required behavior labels appear in the document" do
    doc = File.read(DOC_PATH)

    REQUIRED_BEHAVIORS.each do |behavior|
      assert_includes doc, behavior
    end
  end

  test "readiness table has one row per required behavior with all required columns" do
    doc = File.read(DOC_PATH)
    rows = table_rows(doc)

    assert_equal REQUIRED_BEHAVIORS.sort, rows.map { |row| row.fetch("behavior") }.sort

    rows.each do |row|
      assert_includes ALLOWED_STATUSES, row.fetch("status")
      assert row.fetch("code_path").present?, "#{row.fetch("behavior")} is missing code path"
      assert row.fetch("test_path").present?, "#{row.fetch("behavior")} is missing test path"
      assert row.fetch("migration_risk").present?, "#{row.fetch("behavior")} is missing migration risk"
      assert row.fetch("cutover_requirement").present?, "#{row.fetch("behavior")} is missing cutover requirement"
    end
  end

  test "no row is marked open unless listed in Open items" do
    doc = File.read(DOC_PATH)
    open_items = open_items_section(doc)

    table_rows(doc).each do |row|
      next unless row.fetch("status") == "open"

      behavior = row.fetch("behavior")
      assert_includes open_items, behavior, "#{behavior.inspect} is open but not listed in Open items"
    end
  end

  test "referenced test files exist" do
    doc = File.read(DOC_PATH)
    referenced_tests = doc.scan(%r{test/[A-Za-z0-9_./-]+_test\.rb}).uniq

    assert referenced_tests.any?, "Expected readiness doc to reference test files"
    referenced_tests.each do |path|
      assert File.exist?(Rails.root.join(path)), "Referenced test file does not exist: #{path}"
    end
  end

  private

  def table_rows(doc)
    doc.lines.filter_map do |line|
      next unless line.start_with?("| ")
      next if line.include?("|---")
      next if line.start_with?("| Required behavior")

      cells = line.strip.split("|").map(&:strip).reject(&:empty?)
      next unless cells.size == 6

      {
        "behavior" => cells[0],
        "status" => cells[1],
        "code_path" => cells[2],
        "test_path" => cells[3],
        "migration_risk" => cells[4],
        "cutover_requirement" => cells[5]
      }
    end
  end

  def open_items_section(doc)
    doc.split(/^## Open items\s*$/).last.to_s
  end
end
