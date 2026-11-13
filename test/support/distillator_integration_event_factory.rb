module DistillatorIntegrationEventFactory
  def build_publishable_event(seedurl:, rdf_uri:, algorithm_value:, render_js:, initial_title:, json_post: false)
    website = Website.create!(
      name: seedurl.humanize,
      seedurl: seedurl,
      graph_name: "https://fixtures.example/#{seedurl}",
      default_language: "en"
    )
    event_page = Webpage.create!(
      website: website,
      rdfs_class: rdfs_classes(:one),
      url: "https://fixtures.example/#{seedurl}/event",
      rdf_uri: rdf_uri,
      language: "en",
      archive_date: Time.zone.parse("2026-06-01T00:00:00Z")
    )
    place_page = Webpage.create!(
      website: website,
      rdfs_class: rdfs_classes(:place),
      url: "https://fixtures.example/#{seedurl}/place",
      rdf_uri: "#{rdf_uri}-place",
      language: "en",
      archive_date: Time.zone.parse("2026-06-01T00:00:00Z")
    )

    Source.create!(
      website: website,
      property: properties(:two),
      algorithm_value: "manual=Main Hall",
      selected: true,
      selected_by: "test",
      render_js: false
    ).tap do |source|
      Statement.create!(
        webpage: place_page,
        source: source,
        cache: "Main Hall",
        status: "ok",
        status_origin: "test",
        cache_refreshed: 1.day.ago,
        cache_changed: 1.day.ago,
        selected_individual: true
      )
    end

    title_source = Source.create!(
      website: website,
      property: properties(:four),
      algorithm_value: algorithm_value,
      selected: true,
      selected_by: "test",
      language: "en",
      render_js: render_js
    )
    title_statement = Statement.create!(
      webpage: event_page,
      source: title_source,
      cache: initial_title,
      status: "initial",
      status_origin: "test",
      cache_refreshed: 1.day.ago,
      cache_changed: 1.day.ago,
      selected_individual: true
    )
    if json_post
      allow_scrape_option_json_post!(title_statement)
    end

    create_support_statement!(website:, webpage: event_page, property: properties(:ten), cache: "[\"2026-05-10T19:30:00-04:00\"]")
    create_support_statement!(website:, webpage: event_page, property: properties(:location), cache: "[\"Main Hall\",\"Place\",[\"Main Hall\",\"#{rdf_uri}-place\"]]")

    [website, event_page, title_statement]
  end

  def allow_scrape_option_json_post!(statement)
    statement
  end

  def create_support_statement!(website:, webpage:, property:, cache:)
    source = Source.create!(
      website: website,
      property: property,
      algorithm_value: "manual=#{property.label}",
      selected: true,
      selected_by: "test",
      render_js: false
    )
    Statement.create!(
      webpage: webpage,
      source: source,
      cache: cache,
      status: "ok",
      status_origin: "test",
      cache_refreshed: 1.day.ago,
      cache_changed: 1.day.ago,
      selected_individual: true
    )
  end
end
