# frozen_string_literal: true

require "test_helper"

# Deliberately use an FK-valid minimal dataset. The legacy global fixtures
# require superuser-only trigger disabling and must not mask QA preview failures.
class DanseDansePairingPreviewTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @website = Website.create!(
      name: "Danse Danse original", seedurl: "dansedanse-ca",
      graph_name: "https://example.org/dansedanse",
      default_language: "fr", distillator_mode: "legacy"
    )
  end

  test "pairing button is visible only for the eligible QA copy" do
    get website_path(@website)
    assert_response :success
    assert_select "#qa-multilingual-pairing", count: 0

    post copy_for_qa_website_path(@website), params: { test_copy_seedurl: "dansedansetest-ca" }
    assert_response :see_other
    copy = Website.find_by!(seedurl: "dansedansetest-ca")

    get website_path(copy)
    assert_response :success
    assert_select "#qa-multilingual-pairing form[action='#{preview_multilingual_pairing_website_path(copy)}']", count: 1
    assert_select "#qa-multilingual-pairing form[method='post'] input[type='submit'][value='Preview multilingual pairing']", count: 1
  end

  test "original website cannot execute pairing preview" do
    ResourceLists::DanseDanseKeyedPreview.expects(:call).never
    post preview_multilingual_pairing_website_path(@website)
    assert_response :forbidden
  end

  test "QA pairing preview renders diagnostics without writing database records" do
    copy = Websites::CreateTestCopy.call(source: @website).website
    preview = ResourceLists::DanseDanseKeyedPreview::Result.new(
      status: "needs_review",
      rows: [{ key: "sample", en: "https://www.dansedanse.ca/en/shows/sample",
        fr: "https://www.dansedanse.ca/fr/spectacles/sample",
        rdf_uri: "http://kg.footlight.io/resource/dansedansetest-ca_sample",
        condition: "existing_pair" }],
      errors: ["Unmatched translation key: extra"], counts: { "en" => 2, "fr" => 1 },
      digest: "sample-digest", unmatched_keys: ["extra"],
      fetch_paths: { "en" => "native", "fr" => "native" }
    )
    ResourceLists::DanseDanseKeyedPreview.expects(:call).with(website: copy).returns(preview)

    assert_no_difference ["Website.count", "Webpage.count", "Statement.count"] do
      post preview_multilingual_pairing_website_path(copy)
    end
    assert_response :success
    assert_select "h1", text: /multilingual pairing preview/i
    assert_select "strong", text: /UNVERIFIED/
    assert_select "td", text: "sample"
    assert_select "li", text: "Unmatched translation key: extra"
  end
end
