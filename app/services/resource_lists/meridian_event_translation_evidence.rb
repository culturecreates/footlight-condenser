# frozen_string_literal: true

require "digest"
require "nokogiri"
require "uri"

module ResourceLists
  # Extract explicit translation relationships from two event documents.
  # A translated title, analogous slug, same page position or common node
  # number alone is NOT proof. Does not mint, update or query RDF identities.
  class MeridianEventTranslationEvidence
    ROOT = "meridiancentrepointe.com"
    MAX_BYTES = 5 * 1024 * 1024

    def self.call(urls:, documents:)
      raise ArgumentError, "Expected exactly EN and FR URLs and HTML" unless
        urls.keys.map(&:to_s).sort == %w[en fr] && documents.keys.map(&:to_s).sort == %w[en fr]

      rows = %w[en fr].to_h do |lang|
        url = urls.fetch(lang) { urls.fetch(lang.to_sym) }
        html = documents.fetch(lang) { documents.fetch(lang.to_sym) }
        [lang, inspect_page(lang, url, html)]
      end
      reciprocal = %w[en fr].all? do |lang|
        opposite = lang == "en" ? "fr" : "en"
        rows.dig(lang, :head_alternates, opposite)&.include?(rows.dig(opposite, :requested_url))
      end
      valid = rows.values.all? { |row| row[:state] == "observed" }
      { status: valid && reciprocal ? "verified_reciprocal_translation" : "unverified",
        reciprocal_head_alternates: !!reciprocal, pages: rows,
        evidence_scope: "Operator or read-only HTTP HTML evidence only; not proof of live inventory completeness",
        action: "none", rdf_minted: 0 }
    end

    def self.inspect_page(language, url, html)
      expected = URI.parse(url)
      raise ArgumentError, "Unexpected event URL" unless expected.scheme == "https" &&
        expected.host == ROOT && expected.userinfo.nil? && expected.path.start_with?("/#{language}/") &&
        expected.query.nil? && expected.fragment.nil?
      raise ArgumentError, "Missing or oversized document" unless html.is_a?(String) && html.bytesize.between?(1, MAX_BYTES)

      doc = Nokogiri::HTML(html)
      title = doc.at_css("head title")&.text.to_s.squish
      page_lang = doc.at_css("html")&.[]("lang").to_s.strip.downcase
      links = doc.css("a[href]").size
      evidence = Distillator::PageEvidence.call(body: html)
      head_alternates = Hash.new { |h, k| h[k] = [] }
      doc.css('head link[rel~="alternate"][hreflang][href]').each do |node|
        lang = node["hreflang"].to_s.downcase.split("-").first
        next unless %w[en fr].include?(lang)
        alt = safe_meridian_url(node["href"], url)
        head_alternates[lang] << alt if alt
      end
      head_alternates = head_alternates.transform_values { |values| values.uniq.sort }
      canonical = doc.at_css('head link[rel~="canonical"][href]')
      canonical_url = canonical && safe_meridian_url(canonical["href"], url)
      shortlinks = doc.css('head link[rel~="shortlink"][href]').filter_map do |node|
        ref = safe_meridian_url(node["href"], url)
        ref if ref && URI.parse(ref).path.match?(%r{\A/node/\d+\z})
      end.uniq
      reasons = []
      reasons << "rejected_page_evidence: #{evidence.reasons.join(',')}" if evidence.flagged?
      reasons << "missing_page_title_or_navigation" if title.empty? || links < 5
      reasons << "wrong_document_language: #{page_lang}" if page_lang.present? && page_lang.split("-").first != language
      reasons << "page_not_found" if title.match?(/\b(?:404|not found|page introuvable)\b/i)
      reasons << "canonical_not_requested_url" if canonical && canonical_url != url
      { requested_url: url, state: reasons.empty? ? "observed" : "blocked",
        errors: reasons, sha256: Digest::SHA256.hexdigest(html), bytes: html.bytesize,
        title: title, html_language: page_lang, head_alternates: head_alternates,
        canonical: canonical_url, drupal_shortlinks: shortlinks,
        page_evidence: evidence.to_signals }
    rescue URI::InvalidURIError => error
      raise ArgumentError, "Invalid URL #{url.inspect}: #{error.message}"
    end
    private_class_method :inspect_page

    def self.safe_meridian_url(href, base)
      uri = URI.join(base, href.to_s)
      return unless uri.scheme == "https" && uri.host == ROOT && uri.port == 443 &&
        uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end
    private_class_method :safe_meridian_url
  end
end
