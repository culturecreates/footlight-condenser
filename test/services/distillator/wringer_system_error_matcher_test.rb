require "test_helper"

class Distillator::WringerSystemErrorMatcherTest < ActiveSupport::TestCase
  test "binary VCR HTML is safe to classify including French browser challenges" do
    event = '<html><head><title>Événement culturel</title></head><body><h1>Événement culturel</h1></body></html>'.b
    assert_nil match_for(body: event, http_code: 200)

    challenge = '<html><head><title>Un instant, s’il vous plaît…</title></head><body><p>Votre demande est en cours de vérification, veuillez patienter…</p></body></html>'.b
    issue = match_for(body: challenge, http_code: 200)
    assert_equal "browser_challenge_interstitial", issue&.dig(:key)
    assert_equal "page_identity", issue&.dig(:match_details, :source)

    invalid = "<html><title>Caf\xE9</title><body>Ordinary event</body></html>".b
    assert_nil match_for(body: invalid, http_code: 200)
  end

  test "Co-motion Reservatech integration scripts are not a waiting room" do
    html = Rails.root.join("test/fixtures/files/distillator_dsl/co_motion_ticketing_assets.html").read
    assert_nil match_for(body: html, http_code: 200)
    payload = Distillator::FetchService.enrich_wringer_metadata(url: "https://co-motion.ca/spectacles/2freres-origine/",
      result: { status: :ok, body: html, raw_body: html, http_code: 200, headers: { "content-type" => "text/html" }, fetch_path: "legacy" })
    assert_equal true, payload.dig(:wringer, :signals, :transport_success)
    assert_equal true, payload.dig(:wringer, :signals, :content_success)
    assert_nil payload.dig(:wringer, :signals, :blocking_issue_key)
  end

  test "waiting room text in scripts or a secondary link does not reject an event" do
    html = '<h1>Origine</h1><script>const provider = "Reservatech"; const label = "Waiting room";</script>' \
      '<p>2Frères présente Origine.</p><footer><a href="https://reservatech.net">Waiting room</a></footer>'
    assert_nil match_for(body: html, http_code: 200)
  end

  test "genuine Reservatech waiting-room identities still abort with retry and no cache update" do
    ["Reservatech waiting room", "reservatech waiting room", '<title>Waiting room | Reservatech</title><h1>Waiting room</h1>',
      '<title>Reservatech - Waiting room</title><p>Please wait for tickets.</p>',
      '<title>Salle d’attente — Reservatech</title><p>Veuillez patienter.</p>'].each do |html|
      issue = match_for(body: html, http_code: 200)
      assert_equal "system_reservatech_waiting_room", issue[:error_type]
      assert_equal "abort_update", issue[:action]
      assert_equal true, issue[:retry]
      assert_equal false, issue[:cache]
      assert_equal "page_identity", issue.dig(:match_details, :source)
    end
  end

  test "response pricing vetoes waiting-room classifications including zero-priced offers" do
    ["53 $", "53,00 $", "$53.00", "CAD 53.00", "53 CAD", "0 $"].each do |price|
      ["Reservatech waiting room", "Queue-it", "Salle d'attente"].each do |identity|
        html = "<title>#{identity}</title><h1>#{identity}</h1><p>Régulier #{price}</p>"
        assert_nil match_for(body: html, http_code: 200), "#{identity}: #{price}"
      end
    end
  end

  test "structured offer prices in the response veto waiting-room classifications" do
    [
      { "@type" => "Event", "offers" => { "@type" => "Offer", "price" => "53.00", "priceCurrency" => "CAD" } },
      { "@graph" => [{ "@type" => "https://schema.org/AggregateOffer", "lowPrice" => 0 }] },
      { "@type" => "schema:Offer", "price" => 53 }
    ].each do |data|
      html = '<title>Reservatech waiting room</title><script type="application/ld+json">' + data.to_json + '</script>'
      assert_nil match_for(body: html, http_code: 200), data.inspect
    end
    html = '<title>Reservatech waiting room</title><meta itemprop="price" content="0">'
    assert_nil match_for(body: html, http_code: 200)
  end

  test "code comments invalid prices and retained statement values do not veto waiting rooms" do
    [
      '<script>const previousPrice = "$53.00";</script>',
      '<style>p::after { content: "$53.00"; }</style>',
      '<!-- Régulier 53 $ -->',
      '<script type="application/ld+json">{invalid json}</script>',
      '<script type="application/ld+json">{"@type":"Offer","price":"unknown"}</script>',
      '<meta itemprop="price" content="unknown">',
      '<p>53 tickets remaining</p>'
    ].each do |extra|
      html = '<title>Reservatech waiting room</title><h1>Reservatech waiting room</h1>' + extra
      issue = match_for(body: html, http_code: 200, signals: { cached_price: 53 })
      assert_equal "system_reservatech_waiting_room", issue&.dig(:error_type), extra
    end
  end

  test "pricing does not override HTTP errors or explicit Cloudflare and captcha challenges" do
    html = '<title>Reservatech waiting room</title><p>Régulier 53 $</p>'
    assert_equal "http_server_error", match_for(body: html, http_code: 503)[:error_type]
    assert_equal "http_403", match_for(body: html, http_code: 403)[:error_type]
    payload = Distillator::FetchService.enrich_wringer_metadata(url: "https://example.org/event",
      result: { status: :ok, body: html, http_code: 200, headers: { "Cf-Mitigated" => "challenge" } })
    assert_equal false, payload.dig(:wringer, :signals, :content_success)
    assert_equal "cloudflare_response_header", payload.dig(:wringer, :signals, :blocking_issue_key)

    [
      ['<title>Just a moment...</title><p>Cloudflare</p>', "system_cloudflare"],
      ['<title>Robot Check</title><h1>Verify you are human</h1><div class="captcha"></div>', "system_captcha"]
    ].each do |challenge, type|
      assert_equal type, match_for(body: challenge + '<p>53 $</p>', http_code: 200)[:error_type]
    end
  end

  test "Culture Gaspesie cookie explanation and embedded captcha do not reject the event page" do
    html = <<~HTML
      <html><head><title>Dimanche à Sodome - Culture Gaspésie</title>
      <script src="https://challenges.cloudflare.com/turnstile/v0/api.js"></script></head>
      <body><main><h1>Dimanche à Sodome</h1><time>2026-12-01</time></main>
      <footer><ul><li><div>Description</div><div><p>Cloudflare a placé ce témoin pour prendre en charge la gestion des robots Cloudflare.</p></div></li></ul>
      <form><div class="g-recaptcha">CAPTCHA</div></form></footer></body></html>
    HTML
    assert_nil match_for(body: html, http_code: 200)
    payload = Distillator::FetchService.enrich_wringer_metadata(url: "https://example.org/event",
      result: { status: :ok, body: html, raw_body: html, http_code: 200, headers: { "content-type" => "text/html" } })
    assert_equal true, payload.dig(:wringer, :signals, :transport_success)
    assert_equal true, payload.dig(:wringer, :signals, :content_success)
    assert_nil payload.dig(:wringer, :signals, :blocking_issue_key)
  end

  test "genuine Cloudflare and captcha challenge pages still block successful HTTP responses" do
    [
      ['<title>Just a moment...</title><h1>Checking your browser</h1><p>Cloudflare</p>', "system_cloudflare"],
      ['<title>Attention Required! | Cloudflare</title><p>Enable cookies</p>', "system_cloudflare"],
      ['<title>Robot Check</title><h1>Verify you are human</h1><div class="captcha"></div>', "system_captcha"]
    ].each do |html, type|
      issue = match_for(body: html, http_code: 200)
      assert_equal type, issue[:error_type]
      assert_equal "page_identity", issue.dig(:match_details, :source)
      payload = Distillator::FetchService.enrich_wringer_metadata(url: "https://example.org/event",
        result: { status: :ok, body: html, http_code: 200, headers: {} })
      assert_equal false, payload.dig(:wringer, :signals, :content_success)
    end
  end

  test "challenge words in scripts and a secondary form heading do not identify the page" do
    html = '<title>Concert</title><h1>Concert</h1><script>const captcha = "Attention Required Cloudflare";</script><footer><h2>Verify you are human</h2><div class="captcha"></div></footer>'
    assert_nil match_for(body: html, http_code: 200)
    assert_equal "http_403", match_for(body: html, http_code: 403)[:error_type]
  end

  test "explicit Cloudflare challenge header still blocks even with ordinary title and a large body" do
    html = '<title>Concert</title><h1>Concert</h1>' + '<p>Event content</p>' * 10000
    payload = Distillator::FetchService.enrich_wringer_metadata(url: "https://example.org/event",
      result: { status: :ok, body: html, http_code: 200, headers: { "Cf-Mitigated" => "challenge" } })
    assert_equal true, payload.dig(:wringer, :signals, :transport_success)
    assert_equal false, payload.dig(:wringer, :signals, :content_success)
    assert_equal "cloudflare_response_header", payload.dig(:wringer, :signals, :blocking_issue_key)
    assert_equal "signal", payload.dig(:wringer, :signals, :primary_issue_match, "source")
  end

  test "matches high specificity and generic yaml rules in order" do
    assert_equal "system_cloudflare", match_for(body: "Attention Required by Cloudflare", http_code: 200)[:error_type]
    assert_equal "system_queue", match_for(body: "Queue-it Please wait while we redirect you", http_code: 200)[:error_type]
    assert_equal "system_akamai", match_for(body: "Access Denied Reference #123", http_code: 200)[:error_type]
    assert_equal "empty_body", match_for(body: "", http_code: 200)[:error_type]
    assert_equal "html_error_page", match_for(body: "Internal Server Error", http_code: 200)[:error_type]
    assert_equal "redirect_to_listing", match_for(body: "<html>ok</html>", http_code: 200, final_url: "https://example.org/events", signals: { redirect_type: "normal" })[:error_type]
    assert_equal "http_404", match_for(body: "Not Found", http_code: 404)[:error_type]
    assert_equal "http_server_error", match_for(body: "Server Error", http_code: 500)[:error_type]
  end

  test "body blank matches nil and empty string" do
    rules = [["empty_body", { "match" => { "body_blank" => true }, "policy" => { "error_code" => "empty_body", "retry" => false, "cache" => false, "delete" => false } }]]

    nil_match = Distillator::WringerSystemErrorMatcher.call(body: nil, http_code: 200, final_url: "https://example.org/item", rules: rules)
    empty_match = Distillator::WringerSystemErrorMatcher.call(body: "", http_code: 200, final_url: "https://example.org/item", rules: rules)

    assert_equal "empty_body", nil_match[:error_type]
    assert_equal false, nil_match[:retry]
    assert_equal false, nil_match[:cache]
    assert_equal false, nil_match[:delete]
    assert_equal "empty_body", empty_match[:error_type]
  end

  test "matches apify legacy additions" do
    assert_equal "system_reservatech_waiting_room", match_for(body: "Reservatech waiting room", http_code: 200)[:error_type]
    assert_equal "system_salle_attente", match_for(body: "Salle d'attente", http_code: 200)[:error_type]
    assert_equal "system_captcha", match_for(body: "captcha", http_code: 200)[:error_type]
    assert_equal "forbidden_text", match_for(body: "Forbidden", http_code: 200)[:error_type]
    assert_equal "generic_error_text", match_for(body: "<html><body><h1>Une erreur est survenue</h1></body></html>", http_code: 200)[:error_type]
    assert_equal "post_call_observed", match_for(body: "POST call", http_code: 200)[:error_type]
    assert_equal "http_403", match_for(body: "Nope", http_code: 403)[:error_type]
  end

  test "generic error text captures a matched snippet from body text" do
    issue = match_for(body: "<html><body><main><h1>Une erreur est survenue</h1><p>Veuillez reessayer.</p></main></body></html>", http_code: 200)

    assert_equal "generic_error_text", issue[:key]
    assert_equal "body_text", issue.dig(:match_details, :source)
    assert_equal "Une erreur est survenue", issue.dig(:match_details, :pattern)
    assert_match "Une erreur est survenue", issue.dig(:match_details, :snippet)
  end

  test "generic error text does not match ordinary page text with error words in markup" do
    issue = match_for(body: "<html><head><script>var lastError = null;</script></head><body><h1>Festival program</h1><p>Welcome.</p></body></html>", http_code: 200)

    assert_nil issue
  end

  test "matches by hint and signal" do
    assert_equal "blocked_url", match_for(body: ["abort_update"], http_code: nil, hints: ["blocked_url"], signals: { network_status: "blocked" })[:error_type]
    assert_equal "timeout", match_for(body: ["abort_update"], http_code: nil, hints: ["timeout"], signals: { network_status: "failed" })[:error_type]
    assert_equal "ssl_verify_none_fallback", match_for(body: "<html>ok</html>", http_code: 200, hints: ["ssl_verify_none_fallback"], signals: { ssl_verify_none_fallback: true })[:error_type]
    assert_equal "legacy_phantomjs", match_for(body: "<html>ok</html>", http_code: 200, hints: ["legacy_phantomjs"], signals: { fetch_backend: "phantomjs" })[:error_type]
    assert_equal "phantomjs_unavailable", match_for(body: nil, http_code: nil, hints: ["phantomjs_unavailable"], signals: { renderer_unavailable: true, renderer: "legacy_phantomjs" })[:error_type]
    assert_equal "json_post", match_for(body: '{"ok":true}', http_code: 200, signals: { request_method: "POST", content_type: "json" })[:error_type]
  end

  test "all matches can prefer failure over info for primary issue selection" do
    issue_set = Distillator::WringerIssueSet.call(
      body: nil,
      http_code: 500,
      final_url: "https://example.org/item",
      hints: ["legacy_phantomjs"],
      signals: { request_method: "POST", content_type: "json" }
    )

    assert_includes issue_set.matches.map { |match| match[:key] }, "json_post"
    assert_includes issue_set.matches.map { |match| match[:key] }, "http_5xx"
    assert_equal "http_5xx", issue_set.primary[:key]
  end

  test "call prefers failed http issue over warning empty body" do
    issue = Distillator::WringerSystemErrorMatcher.call(
      body: "",
      http_code: 500,
      final_url: "https://example.org/failure",
      hints: ["empty_body"],
      signals: {}
    )

    assert_equal "http_5xx", issue[:key]
    assert_equal "http_server_error", issue[:error_type]
  end

  test "call prefers a listing redirect over empty body without allowing deletion" do
    issue = Distillator::WringerSystemErrorMatcher.call(
      body: "",
      http_code: 200,
      final_url: "https://example.org/events",
      hints: ["empty_body"],
      signals: { redirect_type: "normal" }
    )

    assert_equal "redirect_to_listing", issue[:key]
    assert_equal false, issue[:delete]
  end

  test "trailing-slash event details and listing paths in query values are not listing redirects" do
    %w[
      https://chancentre.com/events/come-toward-the-fire-2026-day-of-knowledge-sharing/
      https://www.culture3r.com/evenements/tommy-neron/
      https://example.org/events/event/?return=/events/
    ].each do |destination|
      issue = match_for(body: '<html><div class="jet-listing-dynamic-field">Event details</div></html>',
        http_code: 200, final_url: destination, signals: { redirect_type: "normal" })

      assert_nil issue, destination
    end
  end

  test "redirects to the home page and named listings still block" do
    %w[https://example.org https://example.org/ https://example.org/events https://example.org/events/
       https://example.org/fr/evenements/ https://example.org/programmation/?lang=fr].each do |destination|
      issue = match_for(
        body: "<html>listing</html>",
        http_code: 200,
        final_url: destination,
        signals: { redirect_type: "normal" }
      )

      assert_equal "redirect_to_listing", issue[:error_type], destination
      assert_equal "abort_update", issue[:action]
      assert_equal false, issue[:delete]
    end
  end

  test "detail page markers block redirect_to_listing legacy body classification" do
    body = <<~HTML
      <html>
        <body class="single single-evenements postid-7167">
          <div class="elementor-location-single">
            <div class="jet-listing-dynamic-field">Listing styles are present</div>
            <h1>Match d'improvisation | LPIA | Sainte-Anne-de-la-Pérade</h1>
            <p>29 janvier 2026</p>
            <p>19:00</p>
          </div>
        </body>
      </html>
    HTML

    issue = match_for(body: body, http_code: 200, final_url: "https://tourismedeschenaux.ca/evenements")

    assert_nil issue
  end

  test "genuine legacy listing fallback still matches redirect_to_listing with snippet" do
    body = <<~HTML
      <html>
        <body>
          <div class="jet-listing-dynamic-field">Listing fallback card</div>
          <div class="listing-grid">All events</div>
        </body>
      </html>
    HTML

    issue = match_for(body: body, http_code: 200, final_url: "https://tourismedeschenaux.ca/evenements")

    assert_equal "redirect_to_listing", issue[:error_type]
    assert_equal false, issue[:delete]
    assert_equal "html", issue.dig(:match_details, :source)
    assert_equal "jet-listing-dynamic-field", issue.dig(:match_details, :pattern)
    assert_match "jet-listing-dynamic-field", issue.dig(:match_details, :snippet)
  end

  test "invalid regex remains non fatal" do
    result = Distillator::WringerSystemErrorMatcher.call(
      body: "ok",
      http_code: 200,
      final_url: "https://example.org/events",
      rules: [["bad_regex", { "match" => { "final_url_patterns" => ["*invalid["] }, "policy" => { "error_code" => "bad_regex" } }]]
    )

    assert_nil result
  end

  test "specific anti bot issue wins over redirect listing when both match" do
    issue_set = Distillator::WringerIssueSet.call(
      body: "<html>Queue-it Please wait while we redirect you</html>",
      http_code: 200,
      final_url: "https://example.com/events",
      signals: { redirect_type: "normal", network_status: "ok" }
    )

    assert_includes issue_set.matches.map { |m| m[:key] }, "queue_it"
    assert_includes issue_set.matches.map { |m| m[:key] }, "redirect_to_listing"
    assert_equal "queue_it", issue_set.primary[:key]
  end

  private

  def match_for(body:, http_code:, final_url: "https://example.org/item", hints: [], signals: {})
    Distillator::WringerSystemErrorMatcher.call(body: body, http_code: http_code, final_url: final_url, hints: hints, signals: signals)
  end
end
