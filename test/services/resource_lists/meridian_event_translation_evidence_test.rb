require "test_helper"

class ResourceLists::MeridianEventTranslationEvidenceTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  ROOT = "https://meridiancentrepointe.com"
  URLS = { "en" => "#{ROOT}/en/solitary-man-neil-diamond-postponed",
    "fr" => "#{ROOT}/fr/solitary-man-neil-diamond-REPORTE" }.freeze

  def html(lang, reciprocal: true, wrong_language: false, canonical: nil)
    other = lang == "en" ? "fr" : "en"
    alternate = reciprocal ? URLS.fetch(other) : "#{ROOT}/#{other}/unrelated"
    <<~HTML
      <!doctype html><html lang="#{wrong_language ? other : lang}">
      <head><title>Solitary Man | Meridian</title>
      <link rel="alternate" hreflang="#{other}" href="#{alternate}">
      <link rel="canonical" href="#{canonical || URLS.fetch(lang)}">
      <link rel="shortlink" href="/node/123"></head>
      <body><nav><a href="/">Home</a><a href="/events">Events</a>
      <a href="/about">About</a><a href="/contact">Contact</a><a href="/calendar">Calendar</a></nav>
      <h1>Solitary Man</h1><p>Event</p></body></html>
    HTML
  end

  test "accepts reciprocal head alternates without deriving an RDF ID" do
    result = ResourceLists::MeridianEventTranslationEvidence.call(urls: URLS,
      documents: { "en" => html("en"), "fr" => html("fr") })
    assert_equal "verified_reciprocal_translation", result[:status]
    assert result[:reciprocal_head_alternates]
    assert_equal 0, result[:rdf_minted]
    assert_equal ["#{ROOT}/node/123"], result.dig(:pages, "en", :drupal_shortlinks)
  end

  test "matching Drupal currentPath IDs strengthen reciprocal translation evidence" do
    documents = %w[en fr].to_h do |lang|
      settings = '<script type="application/json" data-drupal-selector="drupal-settings-json">{"path":{"currentPath":"node/2811"}}</script>'
      [lang, html(lang).sub("</head>", "#{settings}</head>")]
    end
    result = ResourceLists::MeridianEventTranslationEvidence.call(urls: URLS, documents: documents)
    assert_equal "verified_reciprocal_translation", result[:status]
    assert_equal "drupal-node:2811", result[:verified_shared_key]
    assert_equal "2811", result.dig(:pages, "fr", :drupal_node_id)
  end

  test "different Drupal node IDs block an otherwise reciprocal translation" do
    documents = { "en" => html("en"), "fr" => html("fr") }.transform_values.with_index do |body, i|
      settings = %(<script type="application/json" data-drupal-selector="drupal-settings-json">{"path":{"currentPath":"node/#{2811 + i}"}}</script>)
      body.sub("</head>", "#{settings}</head>")
    end
    result = ResourceLists::MeridianEventTranslationEvidence.call(urls: URLS, documents: documents)
    assert_equal "blocked_identity_conflict", result[:status]
    assert result[:node_id_conflict]
    assert_nil result[:verified_shared_key]
  end

  test "one-way translation link is not sufficient" do
    result = ResourceLists::MeridianEventTranslationEvidence.call(urls: URLS,
      documents: { "en" => html("en"), "fr" => html("fr", reciprocal: false) })
    assert_equal "unverified", result[:status]
    refute result[:reciprocal_head_alternates]
  end

  test "wrong HTML language or canonical blocks verification" do
    result = ResourceLists::MeridianEventTranslationEvidence.call(urls: URLS,
      documents: { "en" => html("en"), "fr" => html("fr", wrong_language: true) })
    assert_equal "unverified", result[:status]
    assert_equal "blocked", result.dig(:pages, "fr", :state)
    result = ResourceLists::MeridianEventTranslationEvidence.call(urls: URLS,
      documents: { "en" => html("en", canonical: "#{ROOT}/en/other"), "fr" => html("fr") })
    assert_equal "unverified", result[:status]
  end

  test "missing reciprocal links cannot be replaced by matching slugs" do
    en = html("en").sub(/<link rel="alternate"[^>]+>/, "")
    fr = html("fr").sub(/<link rel="alternate"[^>]+>/, "")
    result = ResourceLists::MeridianEventTranslationEvidence.call(urls: URLS,
      documents: { "en" => en, "fr" => fr })
    assert_equal "unverified", result[:status]
    refute result[:reciprocal_head_alternates]
  end
end
