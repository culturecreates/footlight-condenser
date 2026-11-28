require "test_helper"

class ResourceLists::MeridianSavedPagesComparisonTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  XPATH = "//div[@class='calendar']//a/@href"
  ROOT = "https://meridiancentrepointe.com"

  def html(*slugs, title: "Événements | Meridian", page: 1, last: 2)
    links = slugs.map { |slug| %(<a href="/fr/#{slug}">#{slug}</a>) }.join
    <<~HTML
      <html><head><title>#{title}</title></head><body><header>
      <nav><a href="/fr">Accueil</a><a href="/fr/evenements?page=0">Première</a>
      <a href="/fr/evenements?page=1">2</a><a href="/fr/evenements?page=#{last}" rel="last">Dernière</a></nav></header>
      <h1>Événements</h1><div class="calendar">#{links}</div>
      <footer><a href="/contact">Contact</a><a href="/about">À propos</a></footer>
      </body></html>
    HTML
  end

  test "two browser captures of page one disagree without fabricating a terminal result" do
    rows = [
      { label: "fr2-empty", page: 1, html: html },
      { label: "fr2b-full", page: 1, html: html("a", "b") },
      { label: "fr1-full", page: 0, html: html("c") },
      { label: "fr3-single", page: 2, html: html("scaramouch") }
    ]
    result = ResourceLists::MeridianSavedPagesComparison.call(snapshots: rows, xpath: XPATH)
    assert_equal [1], result[:inconsistent_assigned_page_numbers]
    comparison = result.fetch(:same_url_comparisons).sole
    assert_equal [], comparison.fetch(:first_only)
    assert_equal ["#{ROOT}/fr/a", "#{ROOT}/fr/b"], comparison.fetch(:second_only)
    assert_equal "unverified_empty_extraction", result[:snapshots].first[:state]
    assert_equal 1, result[:snapshots].last[:distinct_event_count]
    assert_match(/UNVERIFIED/, result[:completeness])
  end

  test "same page with reordered events is consistent by content identity" do
    result = ResourceLists::MeridianSavedPagesComparison.call(snapshots: [
      { label: "a", page: 1, html: html("a", "b") },
      { label: "b", page: 1, html: html("b", "a", "a") }
    ], xpath: XPATH)
    assert_empty result[:inconsistent_assigned_page_numbers]
    assert_equal true, result[:same_url_comparisons].first[:same_event_urls]
    assert_equal 1, result[:snapshots].last[:duplicate_xpath_urls]
  end

  test "browser challenge is rejected even when HTTP metadata is not available" do
    challenge = <<~HTML
      <html><head><title>Pardon Our Interruption</title><meta name="robots" content="noindex"></head>
      <body><h1>Pardon Our Interruption</h1><p>We thought you were a bot. Enable cookies and JavaScript.</p></body></html>
    HTML
    result = ResourceLists::MeridianSavedPagesComparison.call(snapshots: [
      { label: "interstitial", page: 1, html: challenge },
      { label: "calendar", page: 1, html: html("a") }
    ], xpath: XPATH)
    assert_equal "rejected", result[:snapshots].first[:state]
    assert_equal [1], result[:inconsistent_assigned_page_numbers]
  end

  test "flags identical HTML assigned to different URLs and mismatched active page" do
    document1 = html("a").sub("<h1>Événements</h1>", '<h1>Événements</h1><span aria-current="page">Page actuelle 1</span>')
    document3 = html("scaramouch").sub("<h1>Événements</h1>", '<h1>Événements</h1><span aria-current="page">Page actuelle 3</span>')
    result = ResourceLists::MeridianSavedPagesComparison.call(snapshots: [
      { label: "fr1", page: 0, html: document1 },
      { label: "fr2b", page: 1, html: document1 },
      { label: "fr2", page: 1, html: document3 },
      { label: "fr3", page: 2, html: document3 }
    ], xpath: XPATH)
    assert_equal %w[fr2b fr2], result[:mismatched_active_page_labels].map { |row| row[:label] }
    assert_equal [[0, 1], [1, 2]], result[:identical_documents_across_assigned_pages].map { |row| row[:assigned_pages] }.sort
    assert_equal [1], result[:inconsistent_assigned_page_numbers]
    assert_equal "unverified_page_identity", result[:snapshots][1][:state]
    assert_match(/not evidence that the server returned different bodies/, result[:interpretation])
  end

  test "rejects missing documents and invalid XPath" do
    input = [{ label: "a", page: 0, html: html("a") }, { label: "b", page: 1, html: html("b") }]
    assert_raises(ResourceLists::MeridianSavedPagesComparison::Invalid) do
      ResourceLists::MeridianSavedPagesComparison.call(snapshots: input, xpath: "//a/text()")
    end
    input[1][:html] = ""
    assert_raises(ResourceLists::MeridianSavedPagesComparison::Invalid) do
      ResourceLists::MeridianSavedPagesComparison.call(snapshots: input, xpath: XPATH)
    end
  end
end
