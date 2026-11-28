# frozen_string_literal: true

require "digest"
require "nokogiri"
require "uri"

module ResourceLists
  # Inspect existing operator-saved calendar HTML, never fetch or import it.
  # Drupal's node-N-title is bound to the event URL inside the same card.
  # The featured-event section uses featured-node-N-title and is ignored.
  class MeridianCalendarCardEvidence
    ROOT = "https://meridiancentrepointe.com"
    PATHS = { "en" => "/en/events", "fr" => "/fr/evenements" }.freeze
    MAX_BYTES = 5 * 1024 * 1024

    def self.call(html:, language:)
      language = language.to_s
      raise ArgumentError, "Unsupported language" unless PATHS.key?(language)
      raise ArgumentError, "Empty or oversized HTML" unless html.is_a?(String) && html.bytesize.between?(1, MAX_BYTES)

      evidence = Distillator::PageEvidence.call(body: html)
      errors = []
      errors << "page_evidence: #{evidence.status}" if evidence.flagged?
      doc = Nokogiri::HTML(html)
      document_language = doc.at_css("html")&.[]("lang").to_s.downcase.split("-").first
      errors << "wrong_document_language" if document_language != language

      active = doc.css('nav.pager a[aria-current="page"][href]').filter_map do |node|
        page_number(node["href"], language)
      end.uniq
      errors << "missing_or_ambiguous_active_page" unless active.one?

      records = []
      featured = 0
      doc.css("article.theatre-listing-teaser").each do |card|
        heading = card.at_css("h2[id]")
        next unless heading
        if heading["id"].to_s.match?(/\Afeatured-node-\d+-title\z/)
          featured += 1
          next
        end
        match = heading["id"].to_s.match(/\Anode-([1-9]\d*)-title\z/)
        next unless match
        links = card.css('a[rel~="bookmark"][href]')
        if links.size != 1
          errors << "ambiguous_bookmark_link: node/#{match[1]}"
          next
        end
        url = event_url(links.first["href"], language)
        if url.nil?
          errors << "invalid_event_url: node/#{match[1]}"
          next
        end
        records << { node_id: match[1], key: "drupal-node:#{match[1]}", url: url }
      end

      errors << "no_drupal_event_cards" if records.empty?
      records.group_by { |row| row[:node_id] }.each do |id, rows|
        errors << "conflicting_urls_for_node: #{id}" if rows.map { |row| row[:url] }.uniq.size != 1
      end
      records.group_by { |row| row[:url] }.each do |url, rows|
        errors << "conflicting_nodes_for_url: #{url}" if rows.map { |row| row[:node_id] }.uniq.size != 1
      end

      { status: errors.empty? ? "observed" : "blocked", language: language,
        page_number: active.one? ? active.first : nil,
        event_cards: records.uniq, featured_cards_ignored: featured,
        sha256: Digest::SHA256.hexdigest(html), errors: errors,
        note: "Offline calendar-card evidence; not a complete or atomic inventory." }
    end

    def self.page_number(href, language)
      uri = URI.join("#{ROOT}#{PATHS.fetch(language)}", href.to_s)
      return unless uri.scheme == "https" && uri.host == URI.parse(ROOT).host && uri.path == PATHS.fetch(language)
      params = URI.decode_www_form(uri.query.to_s)
      return unless params.size == 1 && params.first.first == "page" && params.first.last.match?(/\A(?:0|[1-9]\d*)\z/)
      number = params.first.last.to_i
      number if number < MeridianPager::MAX_PAGES
    rescue URI::InvalidURIError, ArgumentError
      nil
    end
    private_class_method :page_number

    def self.event_url(href, language)
      uri = URI.join("#{ROOT}#{PATHS.fetch(language)}", href.to_s)
      return unless uri.scheme == "https" && uri.host == URI.parse(ROOT).host &&
        uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? &&
        uri.path.start_with?("/#{language}/") && uri.path != PATHS.fetch(language)
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end
    private_class_method :event_url
  end
end
