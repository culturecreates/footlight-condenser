# frozen_string_literal: true

require "digest"
require "nokogiri"
require "uri"

module ResourceLists
  # Read-only inspection of operator-saved Meridian calendar HTML.
  # A browser's visible page number is not evidence that the requested URL
  # yielded its expected contents. Compare the same numbered URL across
  # different navigation paths before treating it as a stable resource.
  class MeridianSavedPagesComparison
    Invalid = Class.new(StandardError)
    ROOT = "https://meridiancentrepointe.com"
    PATHS = { "en" => "/en/events", "fr" => "/fr/evenements" }.freeze
    MAX_BYTES = 5 * 1024 * 1024

    def self.call(snapshots:, xpath:, language: "fr")
      raise Invalid, "Unknown language" unless PATHS.key?(language)
      raise Invalid, "Expected at least two page captures" unless snapshots.is_a?(Array) && snapshots.size.between?(2, 25)
      raise Invalid, "Expected XPath selecting URL attributes" unless xpath.to_s.match?(%r{/(?:@href|@src)\s*\z})
      labels = snapshots.map { |entry| entry.fetch(:label).to_s }
      raise Invalid, "Capture labels must be unique" unless labels.uniq.size == labels.size && labels.all?(&:present?)

      rows = snapshots.map do |entry|
        label = entry.fetch(:label).to_s
        number = Integer(entry.fetch(:page))
        raise Invalid, "#{label}: page out of bounds" unless number.between?(0, MeridianPager::MAX_PAGES - 1)

        html = entry.fetch(:html)
        raise Invalid, "#{label}: missing or oversized HTML" unless html.is_a?(String) && html.bytesize.between?(1, MAX_BYTES)
        url = "#{ROOT}#{PATHS.fetch(language)}?page=#{number}"
        document = Nokogiri::HTML(html)
        nodes = document.xpath(xpath)
        extracted = nodes.map { |node| node.text.to_s.strip }
        accepted, rejected = extracted.partition { |value| valid_event_url?(value, url, language) }
        canonical = accepted.map { |value| URI.join(url, value).to_s }.uniq.sort
        evidence = Distillator::PageEvidence.call(body: html)
        pager = MeridianPager.call(html: html, url: url)
        navigation = document.css("nav, header, footer, [role=navigation]").any?
        title = document.at_css("head title")&.text.to_s.squish
        heading = document.at_css("h1")&.text.to_s.squish
        declared_canonical = document.at_css('link[rel="canonical"]')&.[]("href")
        explicit_active = document.css('[aria-current="page"], .pagination .active, .pager .active').map do |node|
          node.text.to_s.squish[0, 50]
        end.reject(&:blank?).uniq.first(8)
        state = if evidence.flagged?
          evidence.status
        elsif canonical.empty?
          "unverified_empty_extraction"
        elsif title.blank? || (document.css("a[href]").size < 5) || (!navigation && heading.blank?)
          "unverified_document_structure"
        else
          "observed"
        end
        { label: label, requested_url: url, requested_page: number,
          sha256: Digest::SHA256.hexdigest(html), bytes: html.bytesize,
          title: title, heading: heading, declared_canonical: declared_canonical,
          state: state, evidence: evidence.to_signals,
          xpath_hits: nodes.size, distinct_event_count: canonical.size,
          duplicate_xpath_urls: accepted.size - canonical.size,
          invalid_values: rejected.first(5), urls: canonical,
          pager: { numbered: pager.numbered_pages, last: pager.last_page, next: pager.next_page,
            active_labels: explicit_active } }
      rescue Nokogiri::XML::XPath::SyntaxError => error
        raise Invalid, "#{label}: invalid XPath: #{error.message}"
      end

      same_url_comparisons = rows.group_by { |row| row.fetch(:requested_page) }.flat_map do |number, captures|
        captures.combination(2).map do |first, second|
          a, b = first.fetch(:urls), second.fetch(:urls)
          { page: number, first: first.fetch(:label), second: second.fetch(:label),
            same_event_urls: a == b, first_only: a - b, second_only: b - a,
            first_state: first.fetch(:state), second_state: second.fetch(:state) }
        end
      end
      { site: ROOT, language: language, read_only: true, snapshots: rows,
        same_url_comparisons: same_url_comparisons,
        unstable_page_numbers: same_url_comparisons.reject { |row| row.fetch(:same_event_urls) }.map { |row| row.fetch(:page) }.uniq.sort,
        completeness: "UNVERIFIED: saved HTML demonstrates browser results, not a stable live ResourceList inventory" }
    rescue KeyError, ArgumentError => error
      raise Invalid, error.message
    end

    def self.valid_event_url?(value, base, language)
      uri = URI.join(base, value)
      root = URI.parse(ROOT)
      uri.scheme == "https" && uri.host == root.host && uri.port == root.port &&
        uri.userinfo.nil? && uri.fragment.nil? &&
        uri.path.start_with?("/#{language}/") && uri.path != PATHS.fetch(language)
    rescue URI::InvalidURIError
      false
    end
    private_class_method :valid_event_url?
  end
end
