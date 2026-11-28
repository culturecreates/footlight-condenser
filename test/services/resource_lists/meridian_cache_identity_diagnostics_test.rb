require "test_helper"

class ResourceLists::MeridianCacheIdentityDiagnosticsTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  Original = "meridiancentrepointe-com"
  Copy = "meridiancentrepointetest-com"
  ROOT = "http://kg.footlight.io/resource/"

  def inspect_rows(entries, existing)
    ResourceLists::MeridianCacheIdentityDiagnostics.call(entries: entries, events_by_url: existing,
      original_seedurl: Original, qa_seedurl: Copy)
  end

  def row(uri, url: "https://meridiancentrepointe.com/fr/hotel-california", position: 0, rl: 233318)
    { rl_id: rl, position: position, url: url, rdf_uri: uri }
  end

  test "CURIE and expanded URI are the same identity" do
    result = inspect_rows([row("footlight:#{Copy}_foo")],
      { "https://meridiancentrepointe.com/fr/hotel-california" => ["#{ROOT}#{Copy}_foo"] })
    assert_equal({ "expanded_identifier_matches" => 1 }, result[:row_counts_by_kind])
    assert_empty result[:unresolved_rows]
  end

  test "original and QA URI aliases are different identities and flagged conflicts" do
    uri = "footlight:#{Original}_bilingual_hotel-california"
    qa = "footlight:#{Copy}_bilingual_hotel-california"
    rows = [row(uri), row(qa, rl: 233219)]
    result = inspect_rows(rows,
      { "https://meridiancentrepointe.com/fr/hotel-california" => ["#{ROOT}#{Copy}_opaquehash"] })
    assert_equal "original_vs_qa_namespace", result[:conflicting_urls].sole[:classification]
    assert_equal 1, result[:row_counts_by_kind]["original_namespace_vs_qa_webpage"]
    assert_equal 1, result[:row_counts_by_kind]["qa_namespace_distinct_identity"]
    assert_equal 1, result[:unique_unresolved_urls]
  end

  test "QA slug and hashed clone identity must not be assumed equivalent" do
    result = inspect_rows([row("footlight:#{Copy}_bilingual_hotel-california")],
      { "https://meridiancentrepointe.com/fr/hotel-california" => ["#{ROOT}#{Copy}_ae624921c"] })
    assert_equal "qa_namespace_distinct_identity", result[:unresolved_rows].sole[:kind]
  end

  test "same URL with CURIE and expanded equivalent is not a conflict" do
    rows = [row("footlight:#{Copy}_a"), row("#{ROOT}#{Copy}_a", rl: 233219)]
    result = inspect_rows(rows,
      { "https://meridiancentrepointe.com/fr/hotel-california" => ["#{ROOT}#{Copy}_a"] })
    assert_empty result[:conflicting_urls]
  end

  test "missing webpage does not imply unsafe new RDF minting" do
    result = inspect_rows([row("footlight:#{Copy}_scaramouche")], {})
    assert_equal "missing_webpage", result[:unresolved_rows].sole[:kind]
  end
end
