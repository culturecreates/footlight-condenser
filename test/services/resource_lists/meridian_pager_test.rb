require "test_helper"

class ResourceLists::MeridianPagerTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  URL = "https://meridiancentrepointe.com/fr/evenements?page=0"

  test "extracts explicit last page and next link from French pager" do
    html = <<~HTML
      <html><body><nav class="pager">
      <a href="/fr/evenements?page=0">Page 1</a>
      <a href="/fr/evenements?page=1">Page 2</a>
      <a href="/fr/evenements?page=1" rel="next">Page suivante</a>
      <a href="/fr/evenements?page=5" title="Dernière page">Dernière</a>
      </nav></body></html>
    HTML
    result = ResourceLists::MeridianPager.call(html: html, url: URL)
    assert_equal [0, 1, 5], result.numbered_pages
    assert_equal 5, result.last_page
    assert_equal 1, result.next_page
  end

  test "numbered pages alone cannot prove the last page" do
    html = '<a href="/fr/evenements?page=0">1</a><a href="/fr/evenements?page=1">2</a>'
    result = ResourceLists::MeridianPager.call(html: html, url: URL)
    assert_equal [0, 1], result.numbered_pages
    assert_nil result.last_page
  end

  test "ignores unrelated host pagination, foreign paths and unbounded page values" do
    html = <<~HTML
      <a rel="last" href="https://evil.example/fr/evenements?page=3">Last</a>
      <a rel="last" href="/en/events?page=2">Last</a>
      <a rel="last" href="/fr/evenements?page=99">Last</a>
      <a rel="last" href="/fr/evenements?page=2&sort=desc">Last</a>
      <a href="/fr/evenements?page=1">2</a>
    HTML
    result = ResourceLists::MeridianPager.call(html: html, url: URL)
    assert_nil result.last_page
    assert_equal [1], result.numbered_pages
  end

  test "conflicting last-page labels provide no terminal proof" do
    html = '<a rel="last" href="?page=4">Last</a><a rel="last" href="?page=5">Last</a>'
    result = ResourceLists::MeridianPager.call(html: html, url: URL)
    assert_nil result.last_page
  end

  test "English pager labels are recognized" do
    html = '<a aria-label="Last page" href="/en/events?page=6">Go</a><a href="/en/events?page=1">Next ››</a>'
    result = ResourceLists::MeridianPager.call(html: html, url: "https://meridiancentrepointe.com/en/events?page=0")
    assert_equal 6, result.last_page
    assert_equal 1, result.next_page
  end
end
