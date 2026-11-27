require 'test_helper'

class RefreshWebpageJobTest < ActiveJob::TestCase
  # Exercise the real refresh job and real DB constraints without unrelated fixtures.
  self.fixture_table_names = []

  setup do
    @event_class = RdfsClass.find_or_create_by!(name: "Event")
    site = Website.create!(name: "Refresh job original", seedurl: "refresh-job-original",
      graph_name: "https://example.org/refresh-original", default_language: "en")
    @original_page = site.webpages.create!(url: "https://example.org/events/source",
      language: "en", rdf_uri: "http://kg.footlight.io/resource/refresh_job_original",
      rdfs_class: @event_class)
  end

  test "URL-only refresh fails closed when source and clone share a URL" do
    original = @original_page
    copy_site = Website.create!(name: "Danse Danse QA", seedurl: "dansedansetest-ca",
      graph_name: "https://example.org/dansedansetest-ca", default_language: "en")
    clone = Webpage.create!(url: original.url, language: original.language,
      rdf_uri: "rdf:dansedansetest-ca:collision", rdfs_class: original.rdfs_class,
      website: copy_site)
    Distillator::RefreshRunner.expects(:call).never

    assert_raises(RefreshWebpageJob::AmbiguousWebpageUrlError) { RefreshWebpageJob.perform_now(original.url) }
    assert Webpage.exists?(original.id)
    assert Webpage.exists?(clone.id)
  end

  test "ID-scoped refresh touches only the requested website when URLs collide" do
    original = @original_page
    copy_site = Website.create!(name: "Danse Danse QA", seedurl: "dansedansetest-ca",
      graph_name: "https://example.org/dansedansetest-ca", default_language: "en")
    clone = Webpage.create!(url: original.url, language: original.language,
      rdf_uri: "rdf:dansedansetest-ca:collision", rdfs_class: original.rdfs_class,
      website: copy_site)
    Distillator::RefreshRunner.expects(:call).once.with(
      webpage: clone, refresh_helper: ApplicationController.helpers, scrape_options: {}
    ).returns([])
    Distillator::WebpageRemovalCandidate.stubs(:call).returns(
      Distillator::WebpageRemovalCandidate::Result.new(delete: false, reason: :missing_cache)
    )

    RefreshWebpageJob.perform_now(clone.id)
  end

  test "batch refresh enqueues IDs, not shared webpage URLs" do
    website = Website.create!(name: "Danse Danse QA", seedurl: "dansedansetest-ca",
      graph_name: "https://example.org/dansedansetest-ca", default_language: "en")
    page = Webpage.create!(url: "https://www.dansedanse.ca/fr/spectacles/example",
      language: "fr", rdf_uri: "rdf:dansedansetest-ca:example", rdfs_class: @event_class,
      website: website, archive_date: 3.days.from_now)
    copy_site = Website.create!(name: "Danse Danse original", seedurl: "dansedanse-ca",
      graph_name: "https://example.org/dansedanse-ca", default_language: "en")
    Webpage.create!(url: page.url, language: "fr", rdf_uri: "rdf:dansedanse-ca:example",
      rdfs_class: page.rdfs_class, website: copy_site, archive_date: 3.days.from_now)

    assert_enqueued_with(job: RefreshWebpageJob, args: [page.id]) do
      BatchJobsController.new.refresh_upcoming_events_jobs(website.seedurl)
    end
  end

  test "perform delegates refresh to service object" do
    webpage = @original_page
    Distillator::WebpageRemovalCandidate.stubs(:call).returns(
      Distillator::WebpageRemovalCandidate::Result.new(delete: false, reason: :missing_cache)
    )

    Distillator::RefreshRunner.expects(:call).with(
      webpage: webpage,
      refresh_helper: ApplicationController.helpers,
      scrape_options: {}
    ).returns([])

    RefreshWebpageJob.perform_now(webpage.url)
  end

  test "perform destroys webpage when the removal policy authorizes it" do
    webpage = @original_page
    Distillator::RefreshRunner.stubs(:call).returns([])
    Distillator::WebpageRemovalCandidate.stubs(:call).returns(
      Distillator::WebpageRemovalCandidate::Result.new(delete: true, reason: :delete_candidate)
    )

    assert_difference("Webpage.count", -1) do
      RefreshWebpageJob.perform_now(webpage.url)
    end
  end

  test "old listing-redirect cache flags cannot authorize webpage deletion" do
    webpage = @original_page
    key = Distillator::WringerUrlKey.call(webpage.url)
    cache = Distillator::FetchCache.create!(uri_key: key.uri_key, normalized_url: key.normalized_url,
      http_response_code: 200, final_url: "https://example.org/events/", scrape_date: Time.current)
    Distillator::RefreshRunner.stubs(:call).returns([])

    %w[redirect_to_listing redirect_to_listing_legacy_body].each do |issue|
      cache.update_columns(primary_issue_key: issue, delete_candidate: true,
        signals: { "primary_issue_key" => issue, "primary_issue_delete" => true })
      assert_no_difference("Webpage.count") { RefreshWebpageJob.perform_now(webpage.id) }
      assert Webpage.exists?(webpage.id)
    end
  end

  test "failed ResourceList refresh does not queue import or delete its page" do
    Distillator::RefreshRunner.expects(:call).raises(StandardError, "calendar fetch failed")
    Distillator::WebpageRemovalCandidate.expects(:call).never

    assert_no_enqueued_jobs(only: AddWebpagesJob) do
      error = assert_raises(StandardError) do
        RefreshWebpageJob.perform_now(@original_page.id, "resource_list")
      end
      assert_equal "calendar fetch failed", error.message
    end
    assert Webpage.exists?(@original_page.id)
  end

  test "perform preserves scrape options through refresh runner" do
    webpage = @original_page
    Distillator::WebpageRemovalCandidate.stubs(:call).returns(
      Distillator::WebpageRemovalCandidate::Result.new(delete: false, reason: :missing_cache)
    )

    Distillator::RefreshRunner.expects(:call).with(
      webpage: webpage,
      refresh_helper: ApplicationController.helpers,
      scrape_options: {
        force_scrape: true,
        force_scrape_every_hrs: 0,
        render_js: true,
        use_phantomjs: true,
        json_post: true,
        absolute_src: true,
        include_fragment: true
      }
    ).returns([])

    RefreshWebpageJob.perform_now(
      webpage.url,
      {
        force_scrape: true,
        force_scrape_every_hrs: 0,
        render_js: true,
        use_phantomjs: true,
        json_post: true,
        absolute_src: true,
        include_fragment: true
      }
    )
  end
end
