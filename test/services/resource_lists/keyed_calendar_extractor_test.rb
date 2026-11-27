require "test_helper"

module ResourceLists
  class KeyedCalendarExtractorTest < ActiveSupport::TestCase
    # Pure keyed calendar tests must not load unrelated database fixtures.
    self.fixture_table_names = []

    ITEMS = "//li[contains(concat(' ',normalize-space(@class),' '),' listingShows_wrapper ')]".freeze
    URL = ".//h3[contains(@class,'listingShows_title')]/a/@href".freeze
    KEY = ".//div[contains(@class,'listingShows_imgWrapper')]//img/@src".freeze

    test "Cogeco style cards keep their own image key and language-specific URL" do
      html = <<~HTML
        <ul><li class="listingShows_wrapper"><div class="listingShows_imgWrapper"><img src="/cache/mlevac26.jpg"></div>
          <h3 class="listingShows_title"><a href="/en/shows/martin-levac-phil-collins-genesis-live">Show</a></h3></li>
          <li class="listingShows_wrapper"><div class="listingShows_imgWrapper"><img src="/cache/katrine.jpg"></div>
          <h3 class="listingShows_title"><a href="/en/shows/karine-sansregret">Show</a></h3></li></ul>
      HTML
      result = extract(html)
      assert result.valid?
      assert_equal ["/cache/mlevac26.jpg", "/cache/katrine.jpg"], result.records.map { |row| row[:key] }
      assert_equal ["https://example.org/en/shows/martin-levac-phil-collins-genesis-live", "https://example.org/en/shows/karine-sansregret"], result.records.map { |row| row[:url] }
    end

    test "Danse Danse style URLs derive identical key across language prefixes" do
      en = '<div class="section--listing-spectacles__container"><div class="block--spectacle"><div class="block--spectacle__title--info--category"><span>Show</span></div><a href="/en/shows/marie-chouinard-henri-michaux-solos-duos">Show</a></div></div>'
      fr = en.sub('<span>Show</span>', '<span>Spectacle</span>').sub('/en/shows/', '/fr/spectacles/')
      items_en = "//div[contains(concat(' ',normalize-space(@class),' '),' block--spectacle ')][.//span[normalize-space(.)='Show']]"
      items_fr = items_en.gsub("Show", "Spectacle")
      params = {base_url: "https://www.dansedanse.ca/en/shows", url_xpath: "./a[1]/@href", key_xpath: "./a[1]/@href", key_mode: :url_last_segment}
      en_result = KeyedCalendarExtractor.call(html: en, item_xpath: items_en, **params)
      fr_result = KeyedCalendarExtractor.call(html: fr, item_xpath: items_fr, **params.merge(base_url: "https://www.dansedanse.ca/fr/spectacles"))
      assert en_result.valid?, en_result.errors.inspect
      assert fr_result.valid?, fr_result.errors.inspect
      assert_equal en_result.records.first[:key], fr_result.records.first[:key]
      assert_equal "marie-chouinard-henri-michaux-solos-duos", en_result.records.first[:key]
    end

    test "invalid card cannot become successful partial extraction" do
      html = '<li class="listingShows_wrapper"><h3 class="listingShows_title"><a href="/en/shows/a">Show</a></h3></li>'
      result = extract(html)
      refute result.valid?
      assert_match(/key_count=0/, result.errors.first)
    end

    test "off-domain discovered URL is blocked" do
      html = '<li class="listingShows_wrapper"><div class="listingShows_imgWrapper"><img src="/cache/a.jpg"></div><h3 class="listingShows_title"><a href="http://127.0.0.1/private">A</a></h3></li>'
      result = extract(html)
      refute result.valid?
      assert_equal ["out_of_scope_url: 0"], result.errors
    end

    private

    def extract(html)
      KeyedCalendarExtractor.call(html: html, base_url: "https://example.org/en/shows", item_xpath: ITEMS, url_xpath: URL, key_xpath: KEY)
    end
  end
end
