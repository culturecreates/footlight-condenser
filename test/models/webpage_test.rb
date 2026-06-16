require 'test_helper'

class WebpageTest < ActiveSupport::TestCase
  test "public and internal url scopes classify webpages by url scheme" do
    website = build_website("scope-kind")
    public_page = create_webpage(website, suffix: "public", url: "https://example.org/page", rdf_uri: "rdf:scope:public", rdfs_class: rdfs_classes(:one))
    internal_page = create_webpage(website, suffix: "internal", url: "footlight:scope:internal", rdf_uri: "rdf:scope:internal", rdfs_class: rdfs_classes(:person))

    assert_includes Webpage.public_source_urls, public_page
    assert_not_includes Webpage.public_source_urls, internal_page
    assert_includes Webpage.internal_uris, internal_page
    assert_not_includes Webpage.internal_uris, public_page
  end

  test "publishable and not_publishable scopes use existing selected statement rules" do
    website = build_website("scope-publishable")
    publishable_page = create_webpage(website, suffix: "publishable", url: "https://example.org/publishable", rdf_uri: "rdf:scope:publishable", rdfs_class: rdfs_classes(:one))
    create_publishable_statements_for(publishable_page)

    blocked_page = create_webpage(website, suffix: "blocked", url: "https://example.org/blocked", rdf_uri: "rdf:scope:blocked", rdfs_class: rdfs_classes(:one))
    source = Source.create!(
      website: website,
      property: properties(:four),
      language: "en",
      selected: true,
      algorithm_value: "scope-test"
    )
    Statement.create!(webpage: blocked_page, source: source, cache: "", status: "missing")

    assert_includes Webpage.publishable, publishable_page
    assert_not_includes Webpage.publishable, blocked_page
    assert_includes Webpage.not_publishable, blocked_page
  end

  private

  def build_website(seedurl)
    Website.create!(
      name: "Webpage scope #{seedurl}",
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
        algorithm_value: "scope-test"
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
