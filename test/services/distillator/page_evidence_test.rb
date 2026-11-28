require "test_helper"

class Distillator::PageEvidenceTest < ActiveSupport::TestCase
  MERIDIAN_CHALLENGE = <<~HTML.freeze
    <!DOCTYPE html><html><head><noscript><title>Pardon Our Interruption</title></noscript>
    <meta name="robots" content="noindex, nofollow"><script>
      window.reeseSkipExpirationCheck = true;
      window.onProtectionInitialized = function(protection) {};
    </script></head><body><div class="container">
    <h1>Pardon Our Interruption</h1>
    <p>As you were browsing something about your browser made us think you were a bot.</p>
    <p>To regain access, please make sure that cookies and JavaScript are enabled.</p>
    </div></body></html>
  HTML

  test "Meridian-like 200 interstitial is rejected without a provider-specific rule" do
    evidence = Distillator::PageEvidence.call(body: MERIDIAN_CHALLENGE)
    assert_equal "rejected", evidence.status
    assert_includes evidence.reasons, "browser_verification_text"
    assert_includes evidence.reasons, "noindex_page"
    assert_equal "generic_page_challenge", evidence.blocking_key
  end

  test "ordinary event with consent, security references and a captcha widget is not rejected" do
    html = <<~HTML
      <html><head><title>Concert in November</title>
      <script>const hint = "Pardon Our Interruption";</script>
      <meta name="robots" content="index,follow"></head>
      <body><nav><a href="/">Home</a></nav><main>
      <h1>Concert in November</h1><time datetime="2026-11-30">November 30</time>
      <p>The festival uses browser verification for ticketing.</p>
      </main><footer><form><div class="captcha">Verify you are human</div></form></footer>
      </body></html>
    HTML
    evidence = Distillator::PageEvidence.call(body: html)
    assert_equal "observed", evidence.status
    assert_equal 1, evidence.metrics[:dates]
  end

  test "small legitimate event page with no navigation is not rejected" do
    html = '<html><head><title>Small theatre performance</title></head><body><h1>Small theatre performance</h1><p>2026-11-30</p></body></html>'
    assert_equal "observed", Distillator::PageEvidence.call(body: html).status
  end

  test "drastic unrecognized change against accepted baseline is unverified not bot-labelled" do
    links = (1..22).map { |n| %(<a href="/event-#{n}">Show #{n}</a>) }.join
    baseline = "<html><head><title>Calendar</title></head><body><nav>Programs</nav><main>#{links}<time datetime='2026-12-01'>2026-12-01</time>#{'events ' * 3000}</main><footer>Contact</footer></body></html>"
    changed = '<html><head><title>New website</title></head><body><h1>Welcome</h1><p>We are updating our site.</p></body></html>'
    evidence = Distillator::PageEvidence.call(body: changed, baseline_html: baseline)
    assert_equal "unverified", evidence.status
    assert_includes evidence.reasons, "document_shrank"
    assert_includes evidence.reasons, "links_disappeared"
    assert_includes evidence.reasons, "page_identity_changed"
  end

  test "normal calendar change with preserved layout is observed" do
    old = '<html><head><title>Upcoming shows</title></head><body><nav>Events</nav><main><a href="/a">Old</a></main><footer>Contact</footer></body></html>'
    fresh = '<html><head><title>New season</title></head><body><nav>Events</nav><main><a href="/b">New</a></main><footer>Contact</footer></body></html>'
    assert_equal "observed", Distillator::PageEvidence.call(body: fresh, baseline_html: old).status
  end

  test "observed documents are never mutated by result annotation" do
    result = { status: :ok, body: "ok", wringer: { signals: { transport_success: true } } }
    evidence = Distillator::PageEvidence.call(body: "ok")
    assert_same result, Distillator::PageEvidence.annotate_result(result, evidence)
  end
end
