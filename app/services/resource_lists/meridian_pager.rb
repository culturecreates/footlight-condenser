# frozen_string_literal: true

require "nokogiri"
require "uri"

module ResourceLists
  # Conservative pager evidence for a read-only Meridian audit.
  # Requires an actual "last page" link on page zero before claiming an upper
  # bound; an absent next-link by itself is not proof of completeness.
  class MeridianPager
    MAX_PAGES = 25
    Result = Struct.new(:numbered_pages, :last_page, :next_page, keyword_init: true)

    def self.call(html:, url:)
      uri = URI.parse(url)
      root_path = uri.path.sub(%r{/+\z}, "")
      doc = Nokogiri::HTML(html.to_s)
      numbered, last, following = [], [], []
      doc.css("a[href]").each do |link|
        target = URI.join(uri.to_s, link["href"].to_s)
        next unless target.scheme == uri.scheme && target.host == uri.host &&
          target.port == uri.port && target.path.sub(%r{/+\z}, "") == root_path &&
          target.fragment.nil?
        params = URI.decode_www_form(target.query.to_s)
        next unless params.length == 1 && params[0][0] == "page" &&
          params[0][1].match?(/\A(?:0|[1-9]\d*)\z/)
        page = params[0][1].to_i
        next if page >= MAX_PAGES

        numbered << page
        label = [link.text, link["title"], link["aria-label"]].compact.join(" ").squish
        rels = link["rel"].to_s.downcase.split(/\s+/)
        last << page if rels.include?("last") || label.match?(/\b(?:last|derni[eè]re)\b/i)
        following << page if rels.include?("next") || label.match?(/\b(?:next|suivante?)\b/i)
      rescue URI::InvalidURIError, ArgumentError
        next
      end
      # If labels disagree or lack an explicit last-page claim, do not invent
      # a terminal page from the largest numbered link.
      bound = last.uniq.one? ? last.first : nil
      Result.new(numbered_pages: numbered.uniq.sort, last_page: bound, next_page: following.uniq.one? ? following.first : nil)
    rescue URI::InvalidURIError
      Result.new(numbered_pages: [], last_page: nil, next_page: nil)
    end
  end
end
