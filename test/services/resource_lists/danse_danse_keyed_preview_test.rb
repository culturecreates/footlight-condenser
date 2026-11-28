require "test_helper"

module ResourceLists
  class DanseDanseKeyedPreviewTest < ActiveSupport::TestCase
    self.fixture_table_names = []

    def qa_site
      original = Website.create!(name: "Original Danse Danse", seedurl: "dansedanse-ca",
        graph_name: "https://example.org/dansedanse", default_language: "en")
      copy = Website.create!(name: "Danse Danse QA", seedurl: "dansedansetest-ca",
        graph_name: "https://example.org/dansedansetest", default_language: "en",
        distillator_mode: "shadow", test_copy_of_website: original)
      rlist = RdfsClass.find_or_create_by!(name: "ResourceList")
      ResourceLists::DanseDanseKeyedQaRefresh::LANGUAGES.each do |language, config|
        Webpage.create!(website: copy, rdfs_class: rlist, language: language,
          url: "https://www.dansedanse.ca#{config.fetch(:path)}",
          rdf_uri: "urn:qa:calendar:#{language}")
      end
      copy
    end

    def calendar_html(language, *slugs)
      category = language == "en" ? "Show" : "Spectacle"
      path = language == "en" ? "/en/shows" : "/fr/spectacles"
      cards = slugs.map do |slug|
        %(<div class="block--spectacle"><div class="block--spectacle__title--info--category"><span>#{category}</span></div>) +
          %(<a href="#{path}/#{slug}">Example</a></div>)
      end.join
      %(<div class="section--listing-spectacles__container">#{cards}</div>)
    end

    def response(language, *slugs)
      path = language == "en" ? "/en/shows" : "/fr/spectacles"
      { status: :ok, http_code: 200, body: calendar_html(language, *slugs),
        final_url: "https://www.dansedanse.ca#{path}", fetch_path: "native" }
    end

    test "rejects normal websites before fetching or mutating data" do
      original = Website.new(seedurl: "dansedanse-ca")
      Distillator::FetchService.expects(:fetch_result).never
      assert_raises(DanseDanseKeyedPreview::Invalid) { DanseDanseKeyedPreview.call(website: original) }
    end

    test "reads two known calendars and returns diagnostic matches without writing anything" do
      copy = qa_site
      Distillator::FetchService.expects(:fetch_result).with(
        url: "https://www.dansedanse.ca/en/shows", render_js: false,
        scrape_options: {}, mode: :internal
      ).once.returns(response("en", "alpha", "beta"))
      Distillator::FetchService.expects(:fetch_result).with(
        url: "https://www.dansedanse.ca/fr/spectacles", render_js: false,
        scrape_options: {}, mode: :internal
      ).once.returns(response("fr", "beta", "alpha"))

      assert_no_difference ["Website.count", "Webpage.count", "Statement.count"] do
        result = DanseDanseKeyedPreview.call(website: copy)
        assert_equal "needs_review", result.status
        assert_equal 2, result.rows.size
        assert_equal %w[alpha beta], result.rows.map { |row| row[:key] }
        assert_equal %w[new_or_missing_webpage new_or_missing_webpage], result.rows.map { |row| row[:condition] }
        assert_equal({ "en" => 2, "fr" => 2 }, result.counts)
        assert_empty result.errors
      end
    end

    test "failed French fetch blocks report rather than returning partial pairs" do
      copy = qa_site
      Distillator::FetchService.stubs(:fetch_result).with(
        url: "https://www.dansedanse.ca/en/shows", render_js: false,
        scrape_options: {}, mode: :internal
      ).returns(response("en", "alpha"))
      Distillator::FetchService.stubs(:fetch_result).with(
        url: "https://www.dansedanse.ca/fr/spectacles", render_js: false,
        scrape_options: {}, mode: :internal
      ).returns({ status: :abort, http_code: 503, body: nil })
      result = DanseDanseKeyedPreview.call(website: copy)
      assert_equal "blocked", result.status
      assert_empty result.rows
      assert result.errors.any? { |error| error.include?("fr: calendar fetch failed") }
    end

    test "network exceptions fail closed instead of returning partial pairs" do
      copy = qa_site
      Distillator::FetchService.stubs(:fetch_result).with(
        url: "https://www.dansedanse.ca/en/shows", render_js: false,
        scrape_options: {}, mode: :internal
      ).raises(Net::ReadTimeout)
      Distillator::FetchService.stubs(:fetch_result).with(
        url: "https://www.dansedanse.ca/fr/spectacles", render_js: false,
        scrape_options: {}, mode: :internal
      ).returns(response("fr", "alpha"))
      result = DanseDanseKeyedPreview.call(website: copy)
      assert_equal "blocked", result.status
      assert_empty result.rows
      assert result.errors.any? { |error| error.include?("en: preview failed") }
    end

    test "unmatched translations are reported without hiding the discovered key" do
      copy = qa_site
      Distillator::FetchService.stubs(:fetch_result).with(
        url: "https://www.dansedanse.ca/en/shows", render_js: false,
        scrape_options: {}, mode: :internal
      ).returns(response("en", "alpha", "beta"))
      Distillator::FetchService.stubs(:fetch_result).with(
        url: "https://www.dansedanse.ca/fr/spectacles", render_js: false,
        scrape_options: {}, mode: :internal
      ).returns(response("fr", "alpha"))
      result = DanseDanseKeyedPreview.call(website: copy)
      assert_equal "needs_review", result.status
      assert_includes result.unmatched_keys, "beta"
      assert result.errors.any? { |error| error.include?("Unmatched translation key: beta") }
      assert_equal "missing_translation", result.rows.find { |row| row[:key] == "beta" }[:condition]
    end
  end
end
