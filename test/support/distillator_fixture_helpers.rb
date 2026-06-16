module DistillatorFixtureHelpers
  CATEGORY_FILES = {
    simple_static_html_title: "simple_static_title.html",
    xpath_extraction: "xpath_extraction.html",
    xpath_sanitize: "xpath_sanitize.html",
    jsonld_script_extraction: "jsonld_script_event.html",
    relative_src_href: "relative_links.html",
    redirected_url: "redirected_event_final.html",
    failed_fetch_404: "failed_404.html",
    json_post_legacy_only: "json_post_payload.json",
    render_js_legacy_only: "render_js_iframe.html",
    timezone_date_extraction: "timezone_dates.html"
  }.freeze

  def distillator_fixture_path(name)
    Rails.root.join("test", "fixtures", "files", "distillator", CATEGORY_FILES.fetch(name))
  end

  def distillator_fixture_categories
    CATEGORY_FILES.keys
  end
end
