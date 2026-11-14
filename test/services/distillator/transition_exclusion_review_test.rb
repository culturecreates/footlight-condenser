require "test_helper"

class Distillator::TransitionExclusionReviewTest < ActiveSupport::TestCase
  setup do
    @website = Website.create!(name: "Exclusion pilot", seedurl: "exclusion-pilot", default_language: "en",
      graph_name: "https://example.org/exclusions", distillator_mode: "shadow")
    @page = @website.webpages.create!(url: "https://example.org/gone", rdf_uri: "rdf:gone", rdfs_class: rdfs_classes(:one), language: "en")
    @run = publish_unavailable_source_run(@website, url: @page.url)
  end

  test "review preserves event cache mode and completed evidence while changing the fingerprint" do
    original_page = @page.reload.attributes
    original_records = @run.transition_evidences.order(:id).map(&:attributes)
    digest = Distillator::TransitionFingerprint.call(@website)
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    review = nil
    assert_no_difference ["Statement.count", "Webpage.count", "Distillator::FetchCache.count", "Distillator::TransitionRun.count"] do
      review = exclude
    end
    assert_equal @page.url, review.url
    assert_equal "Source removed; verified manually", review.reason
    assert_equal @run.id, review.source_run_id
    assert_equal 404, review.recorded_evidence["http_response_code"]
    assert_equal @page.reload.attributes, original_page
    assert_equal @run.transition_evidences.order(:id).map(&:attributes), original_records
    assert_not_equal digest, Distillator::TransitionFingerprint.call(@website)
    assert_includes @website.transition_run_blocker, "configuration changed"
    assert_equal "shadow", @website.reload.distillator_mode
  end

  test "reason is required and stored review cannot be rewritten" do
    assert_raises(ActiveRecord::RecordInvalid) { exclude(reason: "  ") }
    assert_empty @website.transition_exclusions
    review = exclude
    assert_not review.update(reason: "A different story")
    assert_equal "Source removed; verified manually", review.reload.reason
    assert_raises(Distillator::TransitionExclusionReview::InvalidReview) { exclude }
  end

  test "bilateral 410 also qualifies" do
    @run = publish_unavailable_source_run(@website, url: @page.url, native_code: 410, legacy_code: 410)
    assert exclude.persisted?
  end

  test "one sided failure server failure and Wringer endpoint failure cannot qualify" do
    evidence = @run.transition_evidences.find_by!(check_kind: "fetch_parity")
    original = evidence.details.deep_dup
    [
      { "http_response_code" => 200 },
      { "http_response_code" => 503 },
      { "attempted_condenser_fetch" => false },
      { "condenser_fetch" => { "cache_hit" => true } },
      { "condenser_fetch" => { "cache_hit" => false, "fetch_path" => "legacy" } },
      { "legacy_fetch" => { "force_scrape" => true, "response_http_code" => 404 } },
      { "legacy_fetch" => { "force_scrape" => true, "upstream_http_code" => 503 } },
      { "legacy_fetch" => { "force_scrape" => false, "upstream_http_code" => 404 } }
    ].each do |changes|
      details = original.deep_dup
      details["representative_url_results"].first.merge!(changes)
      evidence.update!(details: details)
      assert_raises(Distillator::TransitionExclusionReview::InvalidReview) { exclude }
    end
    evidence.update!(details: original.merge("fetch_basis" => "stored_cache"))
    assert_raises(Distillator::TransitionExclusionReview::InvalidReview) { exclude }
    assert_empty @website.transition_exclusions
  end

  test "old or other website evidence cannot authorize an exclusion" do
    other = websites(:one)
    assert_raises(Distillator::TransitionExclusionReview::InvalidReview) do
      Distillator::TransitionExclusionReview.create!(website: other, run: @run, url: @page.url, reason: "Removed")
    end
    old = @run
    @run = publish_unavailable_source_run(@website, url: @page.url)
    assert_raises(Distillator::TransitionExclusionReview::InvalidReview) do
      Distillator::TransitionExclusionReview.create!(website: @website, run: old, url: @page.url, reason: "Removed")
    end
  end

  test "in flight checks prevent changing or restoring scope" do
    review = exclude
    Distillator::TransitionRun.request!(website: @website)
    assert_raises(Distillator::TransitionExclusionReview::InvalidReview) do
      Distillator::TransitionExclusionReview.restore!(exclusion: review, reason: "Available again")
    end
    assert_raises(Distillator::TransitionExclusionReview::InvalidReview) { exclude }
    assert_nil review.reload.revoked_at
  end

  test "restore retains the audit and puts the exact URL back in scope" do
    review = exclude
    excluded_digest = Distillator::TransitionFingerprint.call(@website)
    assert_empty Distillator::TransitionCheck.call(website: @website, check_options: { sample_mode: "all" }).representative_webpages
    assert_raises(ActiveRecord::RecordInvalid) do
      Distillator::TransitionExclusionReview.restore!(exclusion: review, reason: " ")
    end
    review.reload
    Distillator::TransitionExclusionReview.restore!(exclusion: review, reason: "Source URL available again")
    assert_equal "Source URL available again", review.reload.revocation_reason
    assert review.revoked_at
    assert_empty @website.transition_exclusions.active
    assert_not_equal excluded_digest, Distillator::TransitionFingerprint.call(@website)
    assert_equal [@page.url], Distillator::TransitionCheck.call(website: @website).representative_webpages.map(&:url)
    assert_not review.update(reason: "Erase the earlier reason")
    assert_equal 1, @website.transition_exclusions.count
    assert exclude.persisted?
    assert_equal 2, @website.transition_exclusions.count
  end

  test "same URL on another website is unaffected and generic fallback honors exclusions" do
    exclude
    other = websites(:one)
    other_page = other.webpages.create!(url: @page.url, rdf_uri: "rdf:other-gone", rdfs_class: rdfs_classes(:one))
    assert_includes Distillator::TransitionCheck.call(website: other, check_options: { sample_mode: "all" }).representative_webpages.map(&:id), other_page.id
    @page.update!(url: "https://example.org/moved")
    assert_equal [@page.id], Distillator::TransitionCheck.call(website: @website).representative_webpages.map(&:id)
  end

  test "unverified records cannot be inserted directly through the model" do
    assert_raises(ActiveRecord::RecordInvalid) do
      @website.transition_exclusions.create!(source_run: @run, url: @page.url, reason: "Removed", recorded_evidence: {})
    end
  end

  test "excluding one URL does not silently drop unreviewed null URLs" do
    blank = @website.webpages.create!(url: nil, rdf_uri: "rdf:null-url", rdfs_class: rdfs_classes(:one))
    exclude
    assert_equal [blank.id], Distillator::TransitionCheck.call(website: @website).representative_webpages.map(&:id)
  end

  test "explicit website deletion destroys its reviews before their supporting runs" do
    review = exclude
    @website.destroy!
    assert_not Distillator::TransitionExclusion.exists?(review.id)
    assert_not Distillator::TransitionRun.exists?(@run.id)
  end

  private

  def exclude(reason: "Source removed; verified manually")
    Distillator::TransitionExclusionReview.create!(website: @website, run: @run, url: @page.url, reason: reason)
  end
end
