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

    def configure_extra_page(copy, language, number)
      list_class = RdfsClass.find_by!(name: "ResourceList")
      path = DanseDanseKeyedQaRefresh::LANGUAGES.fetch(language).fetch(:path)
      copy.webpages.create!(rdfs_class: list_class, language: language,
        url: "https://www.dansedanse.ca#{path}?page=#{number}",
        rdf_uri: "urn:qa:calendar:#{language}:#{number}")
    end

    def paginated_response(language, number, *slugs)
      result = response(language, *slugs)
      suffix = "?page=#{number}"
      result.merge(final_url: result.fetch(:final_url) + suffix)
    end

    test "merges all configured pages independently of EN/FR page positions" do
      copy = qa_site
      configure_extra_page(copy, "en", 2)
      configure_extra_page(copy, "en", 3)
      configure_extra_page(copy, "en", 4)
      configure_extra_page(copy, "fr", 2)
      configure_extra_page(copy, "fr", 3)

      streams = {
        "en" => { 1 => %w[a], 2 => %w[b], 3 => %w[c], 4 => %w[d] },
        "fr" => { 1 => %w[d], 2 => %w[b a], 3 => %w[c] }
      }
      streams.each do |language, pages|
        base = "https://www.dansedanse.ca#{DanseDanseKeyedQaRefresh::LANGUAGES.fetch(language).fetch(:path)}"
        pages.each do |number, slugs|
          Distillator::FetchService.expects(:fetch_result).with(
            url: number == 1 ? base : "#{base}?page=#{number}", render_js: false,
            scrape_options: {}, mode: :internal
          ).once.returns(number == 1 ? response(language, *slugs) : paginated_response(language, number, *slugs))
        end
      end

      assert_no_difference ["Website.count", "Webpage.count", "Statement.count"] do
        result = DanseDanseKeyedPreview.call(website: copy)
        assert_equal "needs_review", result.status
        assert_equal %w[a b c d], result.rows.map { |row| row.fetch(:key) }
        assert_equal({ "en" => 4, "fr" => 3 }, result.page_counts)
        assert_equal({ "en" => 4, "fr" => 4 }, result.counts)
        assert_empty result.errors
        assert_equal 4, result.page_details.fetch("en").size
      end
    end

    test "detects missing configured page without fetching a partial inventory" do
      copy = qa_site
      configure_extra_page(copy, "en", 3)
      Distillator::FetchService.expects(:fetch_result).never
      result = DanseDanseKeyedPreview.call(website: copy)
      assert_equal "blocked", result.status
      assert_empty result.rows
      assert result.errors.any? { |message| message.include?("en: Missing configured pagination page(s): 2") }
    end

    test "failed later page blocks all pairing output instead of falling back to earlier pages" do
      copy = qa_site
      configure_extra_page(copy, "en", 2)
      { "en" => "https://www.dansedanse.ca/en/shows",
        "fr" => "https://www.dansedanse.ca/fr/spectacles" }.each do |language, url|
        Distillator::FetchService.expects(:fetch_result).with(
          url: url, render_js: false, scrape_options: {}, mode: :internal
        ).once.returns(response(language, "a"))
      end
      Distillator::FetchService.expects(:fetch_result).with(
        url: "https://www.dansedanse.ca/en/shows?page=2", render_js: false,
        scrape_options: {}, mode: :internal
      ).returns({ status: :abort, http_code: 503, body: nil })
      result = DanseDanseKeyedPreview.call(website: copy)
      assert_equal "blocked", result.status
      assert_empty result.rows
      assert result.errors.any? { |message| message.include?("en page 2: fetch failed") }
    end

    test "cross-page duplicate key with conflicting URLs never silently overwrites" do
      copy = qa_site
      configure_extra_page(copy, "en", 2)
      { "en" => "https://www.dansedanse.ca/en/shows",
        "fr" => "https://www.dansedanse.ca/fr/spectacles" }.each do |language, url|
        Distillator::FetchService.expects(:fetch_result).with(
          url: url, render_js: false, scrape_options: {}, mode: :internal
        ).once.returns(response(language, "a"))
      end
      Distillator::FetchService.expects(:fetch_result).with(
        url: "https://www.dansedanse.ca/en/shows?page=2", render_js: false,
        scrape_options: {}, mode: :internal
      ).returns({ status: :ok, http_code: 200,
        body: %(<div class="section--listing-spectacles__container"><div class="block--spectacle"><div class="block--spectacle__title--info--category"><span>Show</span></div><a href="/en/shows/a?variant=2">Example</a></div></div>),
        final_url: "https://www.dansedanse.ca/en/shows?page=2", fetch_path: "native" })
      result = DanseDanseKeyedPreview.call(website: copy)
      assert_equal "blocked", result.status
      assert_empty result.rows
      assert result.errors.any? { |message| message.include?("duplicate_key: en:a") }
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
      assert result.errors.any? { |error| error.include?("fr page 1: fetch failed") }
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
      assert result.errors.any? { |error| error.include?("en page 1: preview failed (Net::ReadTimeout)") }
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
