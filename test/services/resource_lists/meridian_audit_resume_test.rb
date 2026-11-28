require "test_helper"
require "tempfile"

class ResourceLists::MeridianAuditResumeTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  Site = Struct.new(:id, :seedurl, :test_copy_of_website_id, keyword_init: true)
  NOW = Time.utc(2026, 11, 28, 19, 30)
  ROOT = "https://meridiancentrepointe.com"

  def site
    Site.new(id: 585, seedurl: "meridiancentrepointetest-com", test_copy_of_website_id: 99)
  end

  def sources
    %w[en fr].to_h do |lang|
      [lang, { source_id: lang == "en" ? 100 : 101, source_sha256: Digest::SHA256.hexdigest(lang), render_js: false }]
    end
  end

  def receipt(lang, number, last: 2)
    path = lang == "en" ? "/en/events" : "/fr/evenements"
    { "url" => "#{ROOT}#{path}?page=#{number}", "status" => nil, "http" => 200,
      "sha256" => Digest::SHA256.hexdigest("HTML #{lang} #{number}"), "bytes" => 12000,
      "capture_mode" => "live_http", "source_id" => sources.fetch(lang).fetch(:source_id),
      "source_sha256" => sources.fetch(lang).fetch(:source_sha256),
      "source_render_js" => false, "final_url" => "#{ROOT}#{path}?page=#{number}",
      "page_evidence" => { "page_validation_status" => "observed" },
      "captured_at" => (NOW - 60).iso8601, "pager_last_page" => last,
      "xpath_hits" => 2, "urls" => ["#{ROOT}/#{lang}/show-#{number}"], "rejected_xpath_values" => [] }
  end

  def report
    { "generated_at" => (NOW - 60).iso8601, "database" => "footlight_condenser_dansedanse_qa",
      "input_mode" => "live_full_bounded", "website_selection" => "unscheduled_qa_copy",
      "inventory_authoritative" => false, "read_only" => true,
      "website" => { "id" => 585, "seedurl" => site.seedurl, "test_copy_of_website_id" => 99 },
      "sources" => sources.transform_values { |s| s.transform_keys(&:to_s) },
      "pages" => { "en" => (0..2).to_h { |n| [n.to_s, receipt("en", n)] },
        "fr" => { "0" => receipt("fr", 0), "1" => receipt("fr", 1),
          "2" => { "url" => "#{ROOT}/fr/evenements?page=2", "status" => "blocked" } } } }
  end

  def examine(json, now: NOW, site_obj: site, current_sources: sources)
    Tempfile.create(["meridian-resume", ".json"]) do |file|
      file.write(JSON.generate(json))
      file.flush
      ResourceLists::MeridianAuditResume.call(path: file.path,
        database: "footlight_condenser_dansedanse_qa",
        website: site_obj, sources: current_sources, now: now)
    end
  end

  test "reuses five validated receipts and leaves blocked FR page two for retry" do
    result = examine(report)
    assert_equal [0, 1, 2], result.pages.fetch("en").keys.sort
    assert_equal [0, 1], result.pages.fetch("fr").keys.sort
    assert result.pages.fetch("en").fetch(2)[:reused_from_report]
    assert_equal "live_http", result.pages.fetch("fr").fetch(1)[:capture_mode]
  end

  test "refuses changed Source, website identity and database provenance" do
    changed = sources
    changed["fr"] = changed.fetch("fr").merge(source_sha256: "changed")
    assert_raises(ResourceLists::MeridianAuditResume::Invalid) { examine(report, current_sources: changed) }
    assert_raises(ResourceLists::MeridianAuditResume::Invalid) do
      examine(report, site_obj: Site.new(id: 586, seedurl: site.seedurl, test_copy_of_website_id: 99))
    end
  end

  test "rejects stale or future-dated receipts" do
    assert_raises(ResourceLists::MeridianAuditResume::Invalid) { examine(report, now: NOW + 3600) }
    broken = report
    broken["pages"]["en"]["0"]["captured_at"] = (NOW + 120).iso8601
    assert_raises(ResourceLists::MeridianAuditResume::Invalid) { examine(broken) }
  end

  test "rejects previously accepted challenge, truncated URL list or missing first page" do
    broken = report
    broken["pages"]["fr"]["0"]["page_evidence"]["page_validation_status"] = "rejected"
    assert_raises(ResourceLists::MeridianAuditResume::Invalid) { examine(broken) }

    broken = report
    broken["pages"]["en"]["1"]["urls"] = []
    assert_raises(ResourceLists::MeridianAuditResume::Invalid) { examine(broken) }

    broken = report
    broken["pages"]["en"].delete("0")
    assert_raises(ResourceLists::MeridianAuditResume::Invalid) { examine(broken) }
  end

  test "rejects attempts to reuse snapshot replay as live evidence" do
    broken = report
    broken["input_mode"] = "operator_snapshots_not_live_proof"
    assert_raises(ResourceLists::MeridianAuditResume::Invalid) { examine(broken) }
  end
end
