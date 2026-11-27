# frozen_string_literal: true

require "nokogiri"
require "uri"

module ResourceLists
  # Offline analysis of already-rendered calendar snapshots. This inspects
  # DOM children and anchor links; it does NOT equate cards with valid events,
  # assert pagination completeness, or request additional pages.
  module RenderedCardAudit
    module_function

    CONTAINER = ".event_pagination_content_wrapper"

    def analyze(pages:)
      raise ArgumentError, "expected nonempty page snapshots" unless pages.is_a?(Array) && pages.any?

      results = pages.map do |entry|
        page = Integer(entry.fetch(:page))
        url = entry.fetch(:url).to_s
        html = entry.fetch(:html)
        raise ArgumentError, "expected rendered HTML string" unless html.is_a?(String)

        doc = Nokogiri::HTML(html)
        container = doc.at_css(CONTAINER)
        cards = container ? container.element_children.each_with_index.map { |node, index|
          card(node, page: page, index: index + 1, url: url)
        } : []
        {
          page: page,
          requested_url: url,
          container_found: !container.nil?,
          direct_elements: cards.length,
          unique_raw_hrefs: cards.flat_map { |item| item[:raw_hrefs] }.uniq.size,
          unique_absolute_hrefs: cards.flat_map { |item| item[:absolute_hrefs] }.uniq.size,
          # A single empty child is often a placeholder, not an event.
          possible_empty_placeholder: cards.length == 1 && cards.first[:raw_hrefs].empty?,
          reported_items_found: doc.at_css(".event_pagination_number_items_found")&.text&.strip,
          ajax_endpoint: doc.at_css("[data-pagination-ajax]")&.[]("data-pagination-ajax"),
          cards: cards
        }
      end

      raw_index = Hash.new { |hash, key| hash[key] = [] }
      absolute_index = Hash.new { |hash, key| hash[key] = [] }
      results.each do |page|
        page[:cards].each do |item|
          item[:raw_hrefs].each { |href| raw_index[href] << { page: item[:page], card: item[:card_index], text: item[:text] } }
          item[:absolute_hrefs].each { |href| absolute_index[href] << { page: item[:page], card: item[:card_index], text: item[:text] } }
        end
      end

      {
        purpose: "offline_rendered_calendar_card_audit",
        verified_completeness: false,
        pages: results,
        total_direct_elements: results.sum { |page| page[:direct_elements] },
        total_unique_raw_hrefs: raw_index.size,
        total_unique_absolute_hrefs: absolute_index.size,
        repeated_raw_hrefs_across_pages: repeated_across_pages(raw_index),
        repeated_absolute_hrefs_across_pages: repeated_across_pages(absolute_index),
        cards_without_links: results.flat_map { |page| page[:cards].select { |card| card[:raw_hrefs].empty? } }
      }
    end

    def card(node, page:, index:, url:)
      anchors = [node, *node.css("a[href]")].select { |item| item.name == "a" && item["href"].to_s.strip != "" }
      raw_hrefs = anchors.map { |anchor| anchor["href"].strip }.uniq
      absolute_hrefs = raw_hrefs.filter_map do |href|
        begin
          uri = URI.join(url, href)
          next unless %w[http https].include?(uri.scheme)
          uri.fragment = nil
          uri.to_s
        rescue URI::InvalidURIError
          nil
        end
      end.uniq
      {
        page: page, card_index: index, tag: node.name, css_class: node["class"].to_s,
        element_id: node["id"].to_s, text: node.text.to_s.gsub(/\s+/, " ").strip[0, 160],
        raw_hrefs: raw_hrefs, absolute_hrefs: absolute_hrefs
      }
    end

    def repeated_across_pages(index)
      index.each_with_object([]) do |(href, references), result|
        next unless references.map { |item| item[:page] }.uniq.size > 1

        result << { href: href, occurrences: references }
      end
    end
  end
end
