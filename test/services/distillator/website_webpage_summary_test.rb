require "test_helper"

class Distillator::WebsiteWebpageSummaryTest < ActiveSupport::TestCase
  test "summarizes webpage totals kinds classes and publishability per website" do
    website_a = build_website("summary-a")
    website_b = build_website("summary-b")

    resource_list_class = RdfsClass.create!(name: "ResourceList")
    web_page_class = RdfsClass.create!(name: "WebPage")
    unknown_class = RdfsClass.create!(name: "Thingish")

    publishable_event = create_webpage(website_a, suffix: "event-publishable", url: "https://example.org/events/1", rdf_uri: "rdf:summary:event:1", rdfs_class: rdfs_classes(:one))
    create_publishable_statements_for(publishable_event)

    create_webpage(website_a, suffix: "event-blocked", url: "https://example.org/events/2", rdf_uri: "rdf:summary:event:2", rdfs_class: rdfs_classes(:one))
    create_webpage(website_a, suffix: "person", url: "footlight:summary:person", rdf_uri: "rdf:summary:person", rdfs_class: rdfs_classes(:person))
    create_webpage(website_a, suffix: "place", url: "footlight:summary:place", rdf_uri: "rdf:summary:place", rdfs_class: rdfs_classes(:place))
    create_webpage(website_a, suffix: "resource-list", url: "https://example.org/resources", rdf_uri: "rdf:summary:resources", rdfs_class: resource_list_class)
    create_webpage(website_a, suffix: "webpage", url: "https://example.org/page", rdf_uri: "rdf:summary:page", rdfs_class: web_page_class)
    create_webpage(website_a, suffix: "other", url: "footlight:summary:other", rdf_uri: "rdf:summary:other", rdfs_class: unknown_class)
    nil_class_page = create_webpage(website_a, suffix: "nil-class", url: "footlight:summary:nil", rdf_uri: "rdf:summary:nil", rdfs_class: rdfs_classes(:one))
    nil_class_page.update_column(:rdfs_class_id, nil)

    create_webpage(website_b, suffix: "website-b", url: "https://example.org/website-b", rdf_uri: "rdf:summary:website-b", rdfs_class: rdfs_classes(:place))

    summaries = Distillator::WebsiteWebpageSummary.for_websites([website_a.id, website_b.id])

    assert_equal 8, summaries.fetch(website_a.id)[:total]
    assert_equal 4, summaries.fetch(website_a.id)[:public_urls]
    assert_equal 4, summaries.fetch(website_a.id)[:internal_uris]
    assert_equal 2, summaries.fetch(website_a.id)[:by_class]["Event"]
    assert_equal 1, summaries.fetch(website_a.id)[:by_class]["Person"]
    assert_equal 1, summaries.fetch(website_a.id)[:by_class]["Place"]
    assert_equal 1, summaries.fetch(website_a.id)[:by_class]["ResourceList"]
    assert_equal 1, summaries.fetch(website_a.id)[:by_class]["WebPage"]
    assert_equal 2, summaries.fetch(website_a.id)[:by_class]["Other"]
    assert_equal 1, summaries.fetch(website_a.id)[:publishable]
    assert_equal 7, summaries.fetch(website_a.id)[:not_publishable]

    assert_equal 1, summaries.fetch(website_b.id)[:total]
    assert_equal 0, summaries.fetch(website_b.id)[:by_class]["Event"]
    assert_equal 0, summaries.fetch(website_b.id)[:publishable]
    assert_equal 1, summaries.fetch(website_b.id)[:not_publishable]
  end

  private

  def build_website(seedurl)
    Website.create!(
      name: "Summary #{seedurl}",
      seedurl: seedurl,
      graph_name: "https://example.org/#{seedurl}",
      default_language: "en"
    )
  end

  def create_webpage(website, suffix:, url:, rdf_uri:, rdfs_class:)
    Webpage.create!(
      url: "#{url}-#{suffix}",
      language: "en",
      rdf_uri: rdf_uri,
      rdfs_class: rdfs_class,
      website: website
    )
  end

  def create_publishable_statements_for(webpage)
    [
      [properties(:four), "Publishable title"],
      [properties(:location), '[["Salle","uri:place"]]'],
      [properties(:six), '["2026-06-01T20:00:00-04:00"]']
    ].each do |property, cache|
      source = Source.create!(
        website: webpage.website,
        property: property,
        language: "en",
        selected: true,
        algorithm_value: "summary-test"
      )

      Statement.create!(
        webpage: webpage,
        source: source,
        cache: cache,
        status: "ok"
      )
      Statement.where(webpage: webpage, source: source).update_all(status: "ok")
    end
  end
end
